#!/bin/zsh
# Offline recovery fixtures: no models, media, network, or live worker.
set -euo pipefail
alignment_project="${0:A:h:h:h}"
alignment_python="${EPISODE_PYTHON:-${alignment_project}/work/whisperx-trial/venv/bin/python}"
"$alignment_python" - "$alignment_project" <<'PY'
from pathlib import Path
from tempfile import TemporaryDirectory
from copy import deepcopy
import hashlib, json, sys, unittest
import numpy as np
project=Path(sys.argv[1])
sys.path.insert(0,str(project/'scripts/episode_pipeline/lib'))
from alignment_recovery import (AlignmentCache, conflict_windows, recover_groups,
    reconcile_display, conflict_indices, word_bounds, normalize_acoustic_result,
    diagnostic_value, capture_acoustic_result, select_cached_path)


def word(start,end,text='word'):
    return dict(word=text,start=start/1000,end=end/1000,score=.9)


def record(number,start,end):
    return dict(id=number,start_ms=start,end_ms=end,words=[word(start,end)],
                review_flags=[],aligned_text=f'Words {number}')


class AcousticBoundaryTests(unittest.TestCase):
    def test_real_numpy_scalars_are_supported_without_changing_values(self):
        raw={'segments':[{'words':[{'word':'Karoo', 'start':np.float64(1.25),
                                  'end':np.float32(2.5), 'score':np.float64(.9)}]}],
             'count':np.int64(1)}
        normalized=normalize_acoustic_result(raw)
        row=normalized['segments'][0]['words'][0]
        self.assertIs(type(row['start']),float)
        self.assertIs(type(row['end']),float)
        self.assertIs(type(normalized['count']),int)
        self.assertEqual(word_bounds(raw['segments'][0]['words']),(1250,2500))
        self.assertEqual(word_bounds(normalized['segments'][0]['words']),(1250,2500))
        json.dumps(normalized,allow_nan=False)

    def test_invalid_values_keep_detailed_diagnostics_and_raw_evidence(self):
        cases=[{'start':np.float64(float('nan')),'end':2},
               {'start':1,'end':np.float32(float('inf'))},
               {'start':True,'end':2}, {'start':'1','end':2},
               {'start':2,'end':1}]
        for timing in cases:
            with self.subTest(timing=timing),TemporaryDirectory() as directory:
                cache=AlignmentCache(directory,{'audio':'a'})
                raw={'segments':[{'words':[dict(word='Karoo',**timing)]}]}
                with self.assertRaisesRegex(ValueError,'Raw result saved'):
                    capture_acoustic_result(cache,{'first_id':1},raw,[{'id':1,'text':'Karoo'}],directory)
                failure=json.loads((Path(directory)/'alignment-failure.json').read_text())
                self.assertEqual(failure['passage_ids'],[1])
                self.assertTrue((Path(directory)/failure['raw_result_file']).is_file())
                self.assertTrue(failure['reason'])
                self.assertEqual(json.loads((Path(directory)/'alignment-validation.json').read_text())['state'],'failed')
                self.assertEqual(len(list(cache.folder.glob('*.json'))),1) # identity only; bad call not cached

    def test_normalized_results_are_checkpointed_and_reused(self):
        with TemporaryDirectory() as directory:
            cache=AlignmentCache(directory,{'audio':'a'})
            request={'first_id':1}
            raw={'segments':[{'words':[dict(word='Karoo',start=np.float64(1),end=np.float64(2))]}]}
            normalized,reused=cache.call(request,lambda:capture_acoustic_result(cache,request,raw,[{'id':1}],directory))
            self.assertFalse(reused)
            again,reused=cache.call(request,lambda:self.fail('Model was called again'))
            self.assertTrue(reused)
            self.assertEqual(normalized,again)


class CacheTests(unittest.TestCase):
    def test_calls_survive_resume_and_are_content_addressed(self):
        with TemporaryDirectory() as directory:
            cache=AlignmentCache(directory,dict(audio='a',baseline='b',journal='j',model='m',settings='s'))
            result,reused=cache.call(dict(first=1,last=2),lambda: {'words':[word(0,100)]})
            self.assertFalse(reused)
            resumed=AlignmentCache(directory,cache.identity)
            again,reused=resumed.call(dict(first=1,last=2),lambda: self.fail('Repeated inference'))
            self.assertTrue(reused)
            self.assertEqual(result,again)
            self.assertEqual(resumed.hits,1)
            for field in cache.identity:
                changed=dict(cache.identity);changed[field]='different'
                other=AlignmentCache(directory,changed)
                _,reused=other.call(dict(first=1,last=2),lambda: {'fresh':True})
                self.assertFalse(reused,field)

    def test_corrupt_checkpoint_is_not_silently_adopted(self):
        with TemporaryDirectory() as directory:
            cache=AlignmentCache(directory,dict(audio='a'))
            cache.call({'id':1},lambda:{'words':[word(0,100)]})
            path=next(p for p in cache.folder.glob('*.json') if p.name!='identity.json')
            value=json.loads(path.read_text());value['result']['words'][0]['end']=5
            path.write_text(json.dumps(value))
            with self.assertRaisesRegex(ValueError,'checkpoint is invalid'):
                cache.call({'id':1},lambda:self.fail('Silent retry'))

    def test_interruption_keeps_completed_call_only(self):
        with TemporaryDirectory() as directory:
            cache=AlignmentCache(directory,{'model':'m'})
            cache.call({'id':1},lambda:{'ok':1})
            def interrupted():raise InterruptedError('cancelled')
            with self.assertRaises(InterruptedError):cache.call({'id':2},interrupted)
            _,reused=AlignmentCache(directory,cache.identity).call({'id':1},lambda:self.fail('Lost completed call'))
            self.assertTrue(reused)
            result,reused=cache.call({'id':2},lambda:{'ok':2})
            self.assertFalse(reused)


class BoundaryTests(unittest.TestCase):
    def test_small_ordered_overlap_retains_raw_words(self):
        original=[record(1,0,1100),record(2,1000,2000)]
        before=deepcopy(original)
        result,boundaries,problems=reconcile_display(original,3000)
        self.assertEqual(problems,[])
        self.assertEqual(result[0]['end_ms'],1050)
        self.assertEqual(result[1]['start_ms'],1050)
        self.assertEqual(result[0]['words'],original[0]['words'])
        self.assertEqual(original,before)
        self.assertEqual(len(boundaries),1)

    def test_large_contained_and_zero_spans_require_review(self):
        for rows in ([record(1,0,2000),record(2,1000,3000)],
                     [record(1,0,2000),record(2,1000,1100)],
                     [record(1,0,0)]):
            with self.subTest(rows=rows):
                _,_,problems=reconcile_display(rows,5000)
                self.assertTrue(problems)
                self.assertTrue(problems[0]['passage_ids'])

    def test_connected_context_windows_merge(self):
        self.assertEqual(conflict_windows([2,3,6],10,2),[(0,8)])

    def test_group_repair_adopts_context_not_just_original_pair(self):
        cues=[dict(id=i+1,start_ms=i*1000,end_ms=(i+1)*1000,text=f'Words {i+1}') for i in range(6)]
        aligned={c['id']:[word(c['start_ms'],c['end_ms'])] for c in cues}
        aligned[3]=[word(2000,4000)]
        called=[]
        def repair(first,last):
            called.append((first,last))
            return {c['id']:[word(c['start_ms']+10,c['end_ms']-10)] for c in cues[first:last+1]}
        with TemporaryDirectory() as directory:
            repairs=recover_groups(cues,aligned,6000,repair,directory)
            self.assertEqual(called,[(0,5)])
            self.assertEqual(word_bounds(aligned[1]),(10,990))
            self.assertEqual(conflict_indices(cues,aligned,6000),[])
            self.assertTrue((Path(directory)/'alignment-conflicts-pass-1.json').exists())
            self.assertTrue((Path(directory)/'alignment-recovery-progress.json').exists())
            self.assertEqual(len(repairs),1)

    def test_unresolved_recovery_is_bounded_and_saves_diagnostics(self):
        cues=[dict(id=1,start_ms=0,end_ms=1000,text='one'),dict(id=2,start_ms=1000,end_ms=2000,text='two')]
        aligned={1:[word(0,1800)],2:[word(1000,1100)]}
        calls=[]
        with TemporaryDirectory() as directory:
            def unchanged(first,last):calls.append((first,last));return deepcopy(aligned)
            recover_groups(cues,aligned,2000,unchanged,directory)
            self.assertEqual(len(calls),3)
            self.assertTrue((Path(directory)/'alignment-conflicts-pass-3.json').exists())
            _,_,problems=reconcile_display([record(1,0,1800),record(2,1000,1100)],2000)
            self.assertTrue(problems)

    def test_nonfinite_word_timing_is_rejected(self):
        with self.assertRaises(ValueError):word_bounds([dict(start=float('nan'),end=1)])


class AlternativeSelectionTests(unittest.TestCase):
    def save_call(self,cache,cues,values):
        request={'first_id':cues[0]['id'],'last_id':cues[-1]['id'],'passages':cues}
        return cache.call(request,lambda:{'segments':[{'words':[w for cue in cues for w in values[cue['id']]]}]})

    def test_repeated_phrase_uses_consistent_cached_alternative(self):
        cues=[{'id':1,'text':'What if?'},{'id':2,'text':'What if?'},{'id':3,'text':'Next.'}]
        aligned={1:[word(0,500,'What'),word(500,1200,'if?')],
                 2:[word(500,800,'What'),word(800,2000,'if?')],
                 3:[word(2100,2400,'Next.')]}
        correct={2:[word(1200,1400,'What'),word(1450,1900,'if?')]}
        original=deepcopy(aligned)
        with TemporaryDirectory() as directory:
            cache=AlignmentCache(directory,{'audio':'a'})
            self.save_call(cache,[cues[1]],correct)
            self.assertTrue(select_cached_path(cues,aligned,3000,cache,directory))
            self.assertEqual(aligned[1],original[1])
            self.assertEqual(aligned[3],original[3])
            self.assertEqual(aligned[2],correct[2])
            report=json.loads((Path(directory)/'alignment-alternative-selection.json').read_text())
            self.assertEqual([c['passage_id'] for c in report['changes']],[2])

    def test_no_complete_path_does_not_partially_adopt(self):
        cues=[{'id':1,'text':'one'},{'id':2,'text':'two'}]
        aligned={1:[word(0,2000,'one')],2:[word(500,1000,'two')]}
        original=deepcopy(aligned)
        with TemporaryDirectory() as directory:
            cache=AlignmentCache(directory,{'audio':'a'})
            self.assertFalse(select_cached_path(cues,aligned,3000,cache,directory))
            self.assertEqual(aligned,original)

    def test_safe_current_path_is_preferred_to_unnecessary_changes(self):
        cues=[{'id':1,'text':'one'},{'id':2,'text':'two'}]
        aligned={1:[word(0,500,'one')],2:[word(600,1000,'two')]}
        original=deepcopy(aligned)
        with TemporaryDirectory() as directory:
            cache=AlignmentCache(directory,{'audio':'a'})
            self.save_call(cache,cues,{1:[word(0,400,'one')],2:[word(700,1200,'two')]})
            self.assertTrue(select_cached_path(cues,aligned,3000,cache,directory))
            self.assertEqual(aligned,original)


class MigrationTests(unittest.TestCase):
    def migrate(self,outputs,old,config):
        script=(project/'scripts/prepare_episode.zsh').read_text()
        block=script[script.index('if old and config!=old:'):script.index('for target,data in [(outputs/')]
        saved=outputs/'config.json';saved.write_text(json.dumps(old))
        exec(compile(block,'resume migration','exec'),dict(old=old,config=config,outputs=outputs,
             code=config['scripts'],saved=saved,Path=Path,hashlib=hashlib,json=json))

    def fixture(self,root):
        outputs=Path(root);checkpoints=outputs/'checkpoints';checkpoints.mkdir()
        artifact=outputs/'baseline.json';artifact.write_text('unchanged baseline')
        (checkpoints/'baseline.json').write_text(json.dumps({'artifacts':{str(artifact):hashlib.sha256(artifact.read_bytes()).hexdigest()}}))
        scripts={
            'scripts/prepare_episode.zsh':'46a4caa9a0f8c6346a44dc74dba81ab5a993951ce49c0f1f835c7df82b4500f9',
            'scripts/episode_pipeline/align_transcript.zsh':'dadfadac7822e79544bdfefb6f5dfbd8f79a6b9c36f1f2b8e1fe61b7c8d86ee2',
            'scripts/episode_pipeline/build_baseline.zsh':'unchanged'}
        old={'audio':'same','scripts':scripts}
        new=deepcopy(old);new['scripts'].update({k:'new' for k in list(scripts)[:2]})
        new['scripts']['scripts/episode_pipeline/lib/alignment_recovery.py']='new helper'
        return outputs,old,new

    def test_pre_alignment_migration_preserves_baseline_and_audits(self):
        with TemporaryDirectory() as directory:
            outputs,old,new=self.fixture(directory)
            self.migrate(outputs,old,new)
            self.assertEqual((outputs/'baseline.json').read_text(),'unchanged baseline')
            self.assertEqual(json.loads((outputs/'config.json').read_text()),new)
            self.assertEqual(len(list(outputs.glob('recovery-migration-*.json'))),1)

    def test_numeric_boundary_fix_migrates_known_failed_predecessor(self):
        with TemporaryDirectory() as directory:
            outputs,old,new=self.fixture(directory)
            old['scripts'].update({
                'scripts/prepare_episode.zsh':'ff7dd92ad0ad00fc3f83f9177a108f701902139ed2d1cd377f61128894ec8410',
                'scripts/episode_pipeline/align_transcript.zsh':'2e34c19710a5f4ddf5180af37feb3be388e786e135ae841c51c5f960489e80fc',
                'scripts/episode_pipeline/lib/alignment_recovery.py':'5d4736c4a65e955a7bd9cbe2740dbaf2e6233494799589ac31191d2c05454196'})
            new=deepcopy(old)
            for name in ('scripts/prepare_episode.zsh','scripts/episode_pipeline/align_transcript.zsh','scripts/episode_pipeline/lib/alignment_recovery.py'):
                new['scripts'][name]='new'
            self.migrate(outputs,old,new)
            self.assertEqual(json.loads((outputs/'config.json').read_text()),new)

    def test_cached_alternative_fix_migrates_known_failed_predecessor(self):
        with TemporaryDirectory() as directory:
            outputs,old,new=self.fixture(directory)
            replacements={
                'scripts/prepare_episode.zsh':'680cd831326e2ff70beebbe273f1bc6a847bd181884aa74e36a92f517e714f06',
                'scripts/episode_pipeline/align_transcript.zsh':'4a1562eb872ac368d21ddd52a238088c2b91840016f2f6a3d4d46b5a69bff04e',
                'scripts/episode_pipeline/lib/alignment_recovery.py':'07de600b56a2ff503c112837befec3811ca21f816413926760f49a3c001595f2'}
            old['scripts'].update(replacements)
            new=deepcopy(old)
            for name in replacements:new['scripts'][name]='new'
            self.migrate(outputs,old,new)
            self.assertEqual(json.loads((outputs/'config.json').read_text()),new)

    def test_completed_changed_or_corrupt_inputs_block_migration(self):
        for change in ('completed','input','helper','artifact'):
            with self.subTest(change=change),TemporaryDirectory() as directory:
                outputs,old,new=self.fixture(directory)
                if change=='completed':(outputs/'checkpoints/align.json').write_text('{}')
                if change=='input':new['audio']='different'
                if change=='helper':new['scripts']['scripts/episode_pipeline/build_baseline.zsh']='changed'
                if change=='artifact':(outputs/'baseline.json').write_text('corrupt')
                with self.assertRaises(SystemExit):self.migrate(outputs,old,new)
                self.assertEqual(json.loads((outputs/'config.json').read_text()),old)

unittest.main(argv=[sys.argv[0]])
PY

#!/bin/zsh
# Fast offline fixtures: no GLiNER import, inference, media or API requests.
set -euo pipefail
rules_project="${0:A:h:h:h}"
exec python3 - "$rules_project" <<'PY'
from pathlib import Path
import json,subprocess,sys,tempfile,unittest
project=Path(sys.argv[1]);source=(project/'scripts/index_episode_local.zsh').read_text().split("<<'PY_INDEX'\n",1)[1].rsplit('\nPY_INDEX',1)[0]
namespace={'__name__':'fixture'};exec(compile(source,'index_episode_local','exec'),namespace)
class Rules(unittest.TestCase):
    def test_no_raw_vocabulary(self):
        rows=[dict(id='1',kind='fossil',name='Bivalve',review='suggested'),dict(id='2',kind='place',name='India',review='confirmed'),dict(id='3',kind='author',name='Deleted',review='confirmed',deleted=True)]
        self.assertEqual([r['id'] for r in namespace['reviewed_entries'](dict(schema_version=1,entries=rows))],['2'])
        with tempfile.TemporaryDirectory() as root:
            registry=Path(root)/'registry.json';target=Path(root)/'export.json'
            rows[1]['aliases']=['raw quotation'];registry.write_text(json.dumps(dict(schema_version=1,entries=rows)))
            namespace['export_vocabulary'](registry,target)
            self.assertEqual(json.loads(target.read_text())['entries'][0]['aliases'],[])
            namespace['export_vocabulary'](registry,target,True)
            self.assertEqual(json.loads(target.read_text())['entries'][0]['aliases'],['raw quotation'])
    def test_mentions_not_titles(self):
        passages=[dict(id=1,text='I study rocks.'),dict(id=2,text='This research was interesting.'),dict(id=3,text='Hello.'),dict(id=4,text='Another paper.')]
        groups=namespace['reference_mentions'](passages,'guid','edition')
        self.assertEqual(len(groups),2)
        self.assertEqual([a['passage_id'] for a in groups[0]['anchors']],[1,2])
        self.assertEqual(groups[0]['status'],'unidentified')
        self.assertFalse(namespace['publication_supported'](passages,0))
        self.assertTrue(namespace['publication_supported']([dict(id=1,text='Published in Nature.'),dict(id=2,text='Title')],1))
    def test_literal_unicode_and_multiple_detectors(self):
        text='🦕 Bivalve and bivalve';passage=dict(id=1,text=text)
        ev=namespace['evidence']('gliner','taxon',text,2,9,.75,'model','revision')
        anchor=namespace['make_anchor']('g','e',passage,2,9,ev);anchors=[]
        namespace['retain_anchor'](anchors,anchor)
        other=namespace['make_anchor']('g','e',passage,2,9,namespace['evidence']('reviewed-dictionary','fossil',text,2,9))
        namespace['retain_anchor'](anchors,other)
        self.assertEqual(anchor['quote'],'Bivalve');self.assertEqual(len(anchors),1)
        self.assertEqual(len(anchors[0]['extraction']),2)
        self.assertEqual(anchors[0]['extraction'][0]['score'],.75)
        self.assertEqual(anchors[0]['extraction'][0]['model_revision'],'revision')
    def test_evaluation_requires_review_and_counts_categories(self):
        with tempfile.TemporaryDirectory() as root:
            review=Path(root)/'review.json';output=Path(root)/'evaluation.json'
            data=dict(schema_version=1,review_complete=False,reviewer='Fixture only',passages=[dict(id=1,text='Example')],
                candidates=[dict(category='fossil',passage_id=1,judgement='accept'),dict(category='place',passage_id=1,judgement='reject')],
                missed_entities=[dict(category='author',passage_id=1,name='Missed author')])
            command=['/bin/zsh',str(project/'scripts/evaluate_local_index.zsh'),'--review',str(review),'--output',str(output)]
            review.write_text(json.dumps(data))
            result=subprocess.run(command,capture_output=True,text=True)
            self.assertNotEqual(result.returncode,0);self.assertFalse(output.exists())
            data['review_complete']=True;review.write_text(json.dumps(data))
            subprocess.run(command,check=True,capture_output=True,text=True)
            counts=json.loads(output.read_text())['categories']
            self.assertEqual(counts['fossil']['precision'],1)
            self.assertEqual(counts['place']['false_candidates'],1)
            self.assertEqual(counts['author']['missed_entities'],1)
            self.assertEqual(counts['author']['recall'],0)
            self.assertIsNone(counts['paper']['recall'])
    def test_refinement_preserves_provenance_and_pending_mentions(self):
        refine=(project/'scripts/refine_episode_index.zsh').read_text().split("<<'PY_REFINE'\n",1)[1].rsplit('\nPY_REFINE',1)[0]
        api={'__name__':'fixture'};exec(compile(refine,'refinement-fixture','exec'),api)
        data=dict(schema_version=1,entries=[dict(id='1',kind='fossil',author_ids=[],anchors=[dict(extraction=[dict(method='gliner',score=.7)])])],
                  unidentified_reference_mentions=[dict(id='pending')])
        result,_=api['apply_review'](data,{}, {},'fixture-model')
        self.assertEqual(result,data)
unittest.main(argv=['offline-rules'],verbosity=2)
PY

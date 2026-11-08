#!/bin/zsh
# Offline regressions only. No media processing, app, or paid requests.
set -euo pipefail
recovery_project="${0:A:h:h:h}"
python3 - "$recovery_project" <<'PY'
from pathlib import Path
import json, sys, tempfile, unittest
project=Path(sys.argv[1])
sys.path.insert(0,str(project/'scripts/episode_pipeline/lib'))
from baseline_timing import prepare_segments, refinement_failure_summary

def cue(start,end,text):return dict(offsets=dict(**{'from':start,'to':end}),text=text)

class RecoveryTests(unittest.TestCase):
    def test_burgess_zero_duration_preserves_passage_and_words(self):
        raw=[cue(4043000,4044000,' I like that.'),cue(4044000,4044000,' Right?'),cue(4044000,4045000," That's what it's like.")]
        segments,repairs=prepare_segments(raw,6527306)
        self.assertEqual([s['text'] for s in segments],[r['text'].strip() for r in raw])
        self.assertEqual([s['id'] for s in segments],[1,2,3])
        self.assertEqual(segments[1]['end_ms']-segments[1]['start_ms'],1)
        self.assertEqual(len(repairs),2)
        self.assertEqual(raw[1]['offsets']['to'],4044000)
        self.assertTrue(all(a['end_ms']<=b['start_ms'] for a,b in zip(segments,segments[1:])))

    def test_end_of_audio_zero_cues_remain_bounded(self):
        segments,repairs=prepare_segments([cue(0,10,'First'),cue(10,10,'Last'),cue(10,10,'word')],10)
        self.assertTrue(all(0<=r['start_ms']<r['end_ms']<=10 for r in segments))
        self.assertEqual(len(repairs),3)

    def test_valid_timings_unchanged(self):
        segments,repairs=prepare_segments([cue(0,20,'Hello'),cue(30,40,'there')],50)
        self.assertEqual(repairs,[])
        self.assertEqual(segments[1]['start_ms'],30)

    def test_small_overlap_is_logged(self):
        segments,repairs=prepare_segments([cue(0,20,'Hello'),cue(19,40,'there')],50)
        self.assertEqual(segments[1]['start_ms'],20)
        self.assertEqual(repairs[0]['original_start_ms'],19)

    def test_untrustworthy_inputs_fail_precisely(self):
        for rows in ([cue(0,10,'')],[cue(10,9,'word')],[cue(0,4000,'one'),cue(1000,4001,'two')],[cue(0,True,'word')]):
            with self.subTest(rows=rows),self.assertRaisesRegex(ValueError,'Baseline failed: passage'):
                prepare_segments(rows,5000)

    def test_refinement_not_reached_is_not_billable(self):
        with tempfile.TemporaryDirectory() as d:
            summary=refinement_failure_summary(Path(d))
            self.assertEqual(summary['state'],'not_reached')
            self.assertFalse(summary['possible_billable_request'])
            self.assertEqual(summary['cost_usd'],0)

    def test_started_request_is_never_reported_as_free(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d);(p/'request-started.json').write_text('{"reserved_usd":0.5}')
            summary=refinement_failure_summary(p)
            self.assertEqual(summary['state'],'interrupted')
            self.assertTrue(summary['possible_billable_request'])

    def test_corrupt_marker_remains_conservative(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d);(p/'request-started.json').write_text('incomplete')
            self.assertTrue(refinement_failure_summary(p)['possible_billable_request'])

unittest.main(argv=[sys.argv[0]])
PY

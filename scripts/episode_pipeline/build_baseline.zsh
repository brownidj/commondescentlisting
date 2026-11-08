#!/bin/zsh
set -euo pipefail
episode_outputs="${EPISODE_OUTPUTS:?Run scripts/prepare_episode.zsh}"
episode_project="${EPISODE_PROJECT:?}"
"${EPISODE_PYTHON:?}" - "$episode_project" "$episode_outputs" <<'PY'
from pathlib import Path
from datetime import datetime,timezone
import hashlib,json,sys
project,outputs=map(Path,sys.argv[1:])
meta=json.loads((outputs/'episode.json').read_text())
raw_bytes=(outputs/'raw-transcript.json').read_bytes()
raw=json.loads(raw_bytes)
duration_ms=round(float(json.loads((outputs/'probes/opus.json').read_text())['format']['duration'])*1000)
sys.path.insert(0,str(project/'scripts/episode_pipeline/lib'))
from baseline_timing import prepare_segments
segments,repairs=prepare_segments(raw.get('transcription',[]),duration_ms)
(outputs/'baseline-timing-repairs.json').write_text(json.dumps(dict(schema_version=1,repairs=repairs),indent=2)+'\n')
baseline=dict(schema_version=1,episode_guid=meta['guid'],
    review=dict(label='Machine transcribed; not reviewed.',date=datetime.now(timezone.utc).date().isoformat(),
        audio_checked=False,note='Whisper.cpp transcription of the retained Opus recording. Scientific names, speaker wording and uncertain passages have not been contextually or manually listening-reviewed.',
        source='raw-transcript.json',source_sha256=hashlib.sha256(raw_bytes).hexdigest()),
    changes=[],unresolved=[],timing_repairs=repairs,segments=segments)
(outputs/'baseline.json').write_text(json.dumps(baseline,indent=2)+'\n')
(outputs/'transcription-summary.json').write_text(json.dumps(dict(passages=len(segments),
    word_count=sum(len(row['text'].split()) for row in segments),audio_duration_ms=duration_ms,
    first_caption_ms=segments[0]['start_ms'],last_caption_ms=segments[-1]['end_ms'],
    raw_transcript_sha256=hashlib.sha256(raw_bytes).hexdigest(),human_reviewed=False,provisional_timing_repairs=len(repairs)),indent=2)+'\n')
print(f"Recorded {len(repairs)} provisional timestamp repairs; words and passage IDs preserved.")
print(f"Prepared {len(segments)} unreviewed passage IDs.")
PY

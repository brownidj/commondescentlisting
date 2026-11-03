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
assert raw['transcription']
duration_ms=round(float(json.loads((outputs/'probes/opus.json').read_text())['format']['duration'])*1000)
segments=[]
previous_end=0
for index,row in enumerate(raw['transcription'],1):
    start,end=row['offsets']['from'],min(row['offsets']['to'],duration_ms)
    text=row['text'].strip()
    assert text and previous_end<=start<end<=duration_ms, f'Raw passage {index} requires inspection.'
    segments.append(dict(id=index,start_ms=start,end_ms=end,text=text))
    previous_end=end
baseline=dict(schema_version=1,episode_guid=meta['guid'],
    review=dict(label='Machine transcribed; not reviewed.',date=datetime.now(timezone.utc).date().isoformat(),
        audio_checked=False,note='Whisper.cpp transcription of the retained Opus recording. Scientific names, speaker wording and uncertain passages have not been contextually or manually listening-reviewed.',
        source='raw-transcript.json',source_sha256=hashlib.sha256(raw_bytes).hexdigest()),
    changes=[],unresolved=[],segments=segments)
(outputs/'baseline.json').write_text(json.dumps(baseline,indent=2)+'\n')
(outputs/'transcription-summary.json').write_text(json.dumps(dict(passages=len(segments),
    word_count=sum(len(row['text'].split()) for row in segments),audio_duration_ms=duration_ms,
    first_caption_ms=segments[0]['start_ms'],last_caption_ms=segments[-1]['end_ms'],
    raw_transcript_sha256=hashlib.sha256(raw_bytes).hexdigest(),human_reviewed=False),indent=2)+'\n')
print(f"Prepared {len(segments)} unreviewed passage IDs.")
PY

#!/bin/zsh
set -euo pipefail
alignment_outputs="${0:A:h}"
alignment_project="${alignment_outputs:h:h}"
alignment_python="${alignment_project}/work/whisperx-trial/venv/bin/python"
"$alignment_python" - "$alignment_project" "$alignment_outputs" <<'PY'
from pathlib import Path
import copy, hashlib, json, sys
project, outputs = map(Path, sys.argv[1:])
base_path = project / 'flutter_app/assets/transcripts/episode-208-karoo-reviewed.json'
base = json.loads(base_path.read_text())
alignment_bytes = (outputs / 'episode-208-karoo-alignment.json').read_bytes()
alignment = json.loads(alignment_bytes)
# Asset paths in the manifest are relative to flutter_app, not the project root.
audio = project / 'flutter_app' / alignment['audio_asset']
assert alignment['audio_identity'] == 'sha256:' + hashlib.sha256(audio.read_bytes()).hexdigest()
assert alignment['source_transcript_sha256'] == hashlib.sha256(base_path.read_bytes()).hexdigest()
assert len(base['segments']) == len(alignment['segments']) == 1032
document = copy.deepcopy(base)
document['audio_identity'] = alignment['audio_identity']
document['alignment'] = {k:v for k,v in alignment.items() if k != 'segments'}
document['playback_sync_offset_ms'] = 0
document['review']['note'] += ' Word timings aligned to the bundled fixed recording with WhisperX; not manually listening-verified.'
document['segments'] = []
prior_changes = {change['line']: change for change in document['changes']}
previous_end = 0
for baseline, cue in zip(base['segments'], alignment['segments']):
    assert cue['id'] == baseline['id'] and cue['baseline_text'] == baseline['text']
    assert previous_end <= cue['start_ms'] < cue['end_ms'] <= alignment['audio_duration_ms']
    previous_end = cue['end_ms']
    document['segments'].append(dict(id=cue['id'], start_ms=cue['start_ms'], end_ms=cue['end_ms'],
        source_start_ms=cue['source_start_ms'], source_end_ms=cue['source_end_ms'], text=cue['aligned_text']))
    if cue['aligned_text'] != baseline['text']:
        prior_changes[cue['id']] = dict(prior_changes.get(cue['id'], {}), line=cue['id'],
            original_text=prior_changes.get(cue['id'], {}).get('original_text', baseline['text']),
            text=cue['aligned_text'], local_correction=True)
    for flag in cue['review_flags']:
        document['unresolved'].append(dict(lines=[cue['id']], reason='Timing: ' + flag))
document['changes'] = list(prior_changes.values())
stem = 'episode-208-karoo-aligned'
(outputs / (stem+'.json')).write_text(json.dumps(document,indent=2)+'\n')
(outputs / (stem+'.txt')).write_text('\n'.join(c['text'] for c in document['segments'])+'\n')
def stamp(ms, separator):
    return f'{ms//3600000:02}:{ms//60000%60:02}:{ms//1000%60:02}{separator}{ms%1000:03}'
vtt, srt = ['WEBVTT\n'], []
for index, cue in enumerate(document['segments'], 1):
    text = cue['text'].replace('\n',' ')
    escaped = text.replace('&','&amp;').replace('<','&lt;').replace('>','&gt;')
    vtt.append(f"{stamp(cue['start_ms'],'.')} --> {stamp(cue['end_ms'],'.')}\n{escaped}\n")
    srt.append(f"{index}\n{stamp(cue['start_ms'],',')} --> {stamp(cue['end_ms'],',')}\n{text}\n")
(outputs / (stem+'.vtt')).write_text('\n'.join(vtt))
(outputs / (stem+'.srt')).write_text('\n'.join(srt))
asset = project / 'flutter_app/assets/transcripts/episode-208-karoo-alignment.json'
asset.write_bytes(alignment_bytes)
docs = project / 'docs/transcripts'
docs.mkdir(exist_ok=True)
for suffix in ['txt','vtt','srt']:
    (docs / (stem+'.'+suffix)).write_bytes((outputs / (stem+'.'+suffix)).read_bytes())
print('Published full-episode alignment asset and JSON/TXT/VTT/SRT deliverables; original transcript and journal untouched.')
PY

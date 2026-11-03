#!/bin/zsh
set -euo pipefail

# ZSH is the launcher; the embedded code calls WhisperX's Python-only alignment
# API. The upstream CLI would transcribe again rather than align our edited text.
trial_outputs="${0:A:h}"
trial_project="${trial_outputs:h:h}"
trial_work="${trial_project}/work/whisperx-trial"
trial_python="${trial_work}/venv/bin/python"
[[ -x "$trial_python" ]]
[[ -s "${trial_outputs}/karoo-first-120s.wav" ]]
trial_run="$(mktemp -d "${trial_outputs}/run-$(date -u +%Y%m%dT%H%M%SZ)-XXXXXX")"
export TORCH_HOME="${trial_work}/torch"
export HF_HOME="${trial_work}/huggingface"
export NLTK_DATA="${trial_work}/nltk_data"
export TOKENIZERS_PARALLELISM=false
# Python.org installations may lack an installed trust bundle. Use the pinned
# environment's CA bundle rather than weakening HTTPS certificate verification.
export SSL_CERT_FILE="$("$trial_python" -m certifi)"
export REQUESTS_CA_BUNDLE="$SSL_CERT_FILE"
mkdir -p "$TORCH_HOME" "$HF_HOME" "$NLTK_DATA" "${trial_work}/models"

"$trial_python" -u - "$trial_project" "$trial_outputs" "$trial_run" <<'PY' > "${trial_run}/alignment.log" 2>&1
import csv
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import platform
import resource
import statistics
import sys
import time
import wave

project, outputs, run = map(Path, sys.argv[1:])
started = time.perf_counter()
import nltk
import torch
import whisperx

torch.set_num_threads(4)
nltk.download('punkt_tab', download_dir=os.environ['NLTK_DATA'], quiet=True, raise_on_error=True)
clip = outputs / 'karoo-first-120s.wav'
asset = project / 'flutter_app/assets/transcripts/episode-208-karoo-reviewed.json'
source = json.loads(asset.read_text())
source_hash = hashlib.sha256(asset.read_bytes()).hexdigest()
with wave.open(str(clip)) as stream:
    clip_duration = stream.getnframes() / stream.getframerate()
guid = source['episode_guid']
journal = Path('/Users/david/Library/Containers/com.example.commonDescentListing/Data/Library/Application Support/com.example.commonDescentListing/transcript-edits') / (guid.encode().hex() + '.json')
journal_bytes = journal.read_bytes() if journal.exists() else None
local = json.loads(journal_bytes) if journal_bytes else None
text = {c['id']: c['text'] for c in source['segments']}
baseline = {c['id']: c for c in source['segments']}
if local:
    assert local['episode_guid'] == guid
    for revision in local['revisions']:
        cue_id = revision['cue_id']
        assert baseline[cue_id]['text'] == revision['baseline_text']
        assert text[cue_id] == revision['before']
        text[cue_id] = revision['after']

cues = [dict(c, text=text[c['id']]) for c in source['segments'] if c['end_ms'] / 1000 <= clip_duration]
inputs = {
    'episode_guid': guid,
    'whisperx_version': importlib.metadata.version('whisperx'),
    'device': 'cpu', 'threads': 4,
    'alignment_model': 'WAV2VEC2_ASR_BASE_960H',
    'audio_sha256': hashlib.sha256(clip.read_bytes()).hexdigest(),
    'audio_duration_seconds': clip_duration,
    'clock_basis': 'Seconds from start of the captured advert-free clip; not the listener advertised stream.',
    'source_asset_sha256': source_hash,
    'local_journal_sha256': hashlib.sha256(journal_bytes).hexdigest() if journal_bytes else None,
    'local_sync_offset_ms_not_applied_to_this_audio': local.get('sync_offset_ms') if local else None,
    'padding_seconds': 1.5,
    'strategy': 'Consecutive passages aligned together in chunks of at most 30 seconds, then mapped back by exact word sequence.',
    'cues': cues,
}
(run / 'input.json').write_text(json.dumps(inputs, indent=2) + '\n')
print(f'Loading aligner for {len(cues)} existing passages; no retranscription.', flush=True)
model, metadata = whisperx.load_align_model(language_code='en', device='cpu', model_dir=str(project / 'work/whisperx-trial/models'))
audio = whisperx.load_audio(str(clip))
groups = []
for cue in cues:
    if not groups or cue['end_ms'] - groups[-1][0]['start_ms'] > 30000:
        groups.append([])
    groups[-1].append(cue)
chunks = []
aligned = {}
for group in groups:
    window_start = max(0, group[0]['start_ms'] / 1000 - 1.5)
    window_end = min(clip_duration, group[-1]['end_ms'] / 1000 + 1.5)
    joined = ' '.join(' '.join(cue['text'].split()) for cue in group)
    result = whisperx.align(
        [dict(start=window_start, end=window_end, text=joined)],
        model, metadata, audio, 'cpu', interpolate_method='ignore',
        return_char_alignments=False,
    )
    words = [word for segment in result['segments'] for word in segment.get('words', [])]
    # Refuse to attach timing to the wrong ID if the aligner changes token order.
    assert [word['word'] for word in words] == joined.split(), 'Aligner word sequence changed; manual mapping required.'
    chunks.append(dict(passage_ids=[cue['id'] for cue in group], result=result))
    index = 0
    for cue in group:
        count = len(cue['text'].split())
        aligned[cue['id']] = (words[index:index + count], window_start, window_end)
        index += count
    print(f"Aligned chunk with passages {group[0]['id']}–{group[-1]['id']}", flush=True)
(run / 'chunks.json').write_text(json.dumps(chunks, indent=2) + '\n')
records = []
for cue in cues:
    words, window_start, window_end = aligned[cue['id']]
    timed = [w for w in words if isinstance(w.get('start'), (float, int)) and isinstance(w.get('end'), (float, int))]
    scored = [w['score'] for w in timed if isinstance(w.get('score'), (float, int))]
    start_ms = round(min(w['start'] for w in timed) * 1000) if timed else None
    end_ms = round(max(w['end'] for w in timed) * 1000) if timed else None
    flags = []
    if not timed:
        flags.append('no_timed_words')
    if len(timed) < len(words):
        flags.append('some_words_without_timing')
    if scored and statistics.mean(scored) < 0.5:
        flags.append('mean_word_score_below_0.5')
    if start_ms is not None and window_start > 0 and start_ms <= window_start * 1000 + 50:
        flags.append('alignment_touches_window_start')
    if end_ms is not None and end_ms >= window_end * 1000 - 50:
        flags.append('alignment_touches_window_end')
    record = {
        'passage_id': cue['id'], 'text': cue['text'],
        'stored_start_ms': cue['start_ms'], 'stored_end_ms': cue['end_ms'],
        'aligned_start_ms': start_ms, 'aligned_end_ms': end_ms,
        'start_change_ms': start_ms - cue['start_ms'] if start_ms is not None else None,
        'end_change_ms': end_ms - cue['end_ms'] if end_ms is not None else None,
        'mean_word_score': statistics.mean(scored) if scored else None,
        'timed_words': len(timed), 'total_words': len(words),
        'window_start_ms': round(window_start * 1000),
        'window_end_ms': round(window_end * 1000),
        'review_flags': flags,
        'word_alignment': words,
    }
    records.append(record)
    print(f"Passage {cue['id']}: {start_ms}–{end_ms} ms; flags={flags}", flush=True)

for previous, current in zip(records, records[1:]):
    if previous['aligned_end_ms'] is not None and current['aligned_start_ms'] is not None and previous['aligned_end_ms'] > current['aligned_start_ms']:
        previous['review_flags'].append('overlaps_next_passage')
        current['review_flags'].append('overlaps_previous_passage')
assert hashlib.sha256(asset.read_bytes()).hexdigest() == source_hash
assert (journal.read_bytes() if journal.exists() else None) == journal_bytes
summary = {
    **{k: v for k, v in inputs.items() if k != 'cues'},
    'passage_count': len(records),
    'passages_with_timed_words': sum(r['timed_words'] > 0 for r in records),
    'flagged_passages': [r['passage_id'] for r in records if r['review_flags']],
    'local_text_corrections_used': [c['id'] for c in cues if c['text'] != baseline[c['id']]['text']],
    'elapsed_seconds_including_model_load': round(time.perf_counter() - started, 3),
    'peak_rss_bytes_macos': resource.getrusage(resource.RUSAGE_SELF).ru_maxrss,
    'platform': platform.platform(),
    'python': platform.python_version(),
    'torch_version': torch.__version__,
    'listener_files_unchanged': True,
    'human_audio_validation': False,
    'adopted_in_app': False,
}
(run / 'alignment.json').write_text(json.dumps(records, indent=2) + '\n')
(run / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
columns = ['passage_id', 'stored_start_ms', 'aligned_start_ms', 'start_change_ms', 'stored_end_ms', 'aligned_end_ms', 'mean_word_score', 'review_flags', 'text']
with (run / 'comparison.tsv').open('w', newline='') as handle:
    writer = csv.DictWriter(handle, fieldnames=columns, delimiter='\t', extrasaction='ignore')
    writer.writeheader()
    for row in records:
        writer.writerow(dict(row, review_flags=';'.join(row['review_flags'])))
print(json.dumps(summary, indent=2), flush=True)
PY
print -r -- "Alignment completed: ${trial_run}"

#!/bin/zsh
set -euo pipefail
alignment_outputs="${EPISODE_OUTPUTS:?Run scripts/prepare_episode.zsh}"
alignment_project="${EPISODE_PROJECT:?}"
alignment_work="${alignment_project}/work/whisperx-trial"
alignment_python="${EPISODE_PYTHON:?}"
export TORCH_HOME="${alignment_work}/torch"
export HF_HOME="${alignment_work}/huggingface"
export NLTK_DATA="${alignment_work}/nltk_data"
export TOKENIZERS_PARALLELISM=false
export SSL_CERT_FILE="$("$alignment_python" -m certifi)"
export REQUESTS_CA_BUNDLE="$SSL_CERT_FILE"
"$alignment_python" -u - "$alignment_project" "$alignment_outputs" <<'PY' > "${alignment_outputs}/alignment.log" 2>&1
from pathlib import Path
import csv, hashlib, importlib.metadata, json, os, statistics, sys, time
from unittest.mock import patch
import torch, whisperx
import whisperx.alignment as whisperx_alignment

class AlignmentWindowTokenizer:
    """Keep the supplied acoustic window intact, including citations like al.'s.

    WhisperX's sentence postprocessor can split inside whitespace-delimited words,
    includes the following character at span ends, and sorts sentences by time.
    Our caller already supplies bounded windows and owns passage segmentation.
    This changes sentence grouping only, not text or acoustic alignment.
    """
    def span_tokenize(self, text):
        return [(0, len(text))] if text else []

def aligned_words_match(text, words):
    return [word.get('word') for word in words] == text.split()

project, outputs = map(Path, sys.argv[1:])
started = time.perf_counter()
torch.set_num_threads(4)
source_path = outputs / 'baseline.json'
source_bytes = source_path.read_bytes()
source = json.loads(source_bytes)
audio_path = Path(os.environ['EPISODE_WORK']) / 'episode/audio.opus'
audio_hash = hashlib.sha256(audio_path.read_bytes()).hexdigest()
audio_bytes = audio_path.read_bytes()
source_audio_hash = (outputs / 'source-checksum.txt').read_text().split()[0]
assert hashlib.sha256((Path(os.environ.get('EPISODE_SOURCE', str(Path(os.environ['EPISODE_WORK']) / 'source.mp3')))).read_bytes()).hexdigest() == source_audio_hash
guid = source['episode_guid']
journal_path = Path(os.environ['EPISODE_JOURNALS']) / (guid.encode().hex() + '.json')
journal_bytes = journal_path.read_bytes() if journal_path.exists() else None
local = json.loads(journal_bytes) if journal_bytes else None
text = {cue['id']: cue['text'] for cue in source['segments']}
baseline = {cue['id']: cue for cue in source['segments']}
if local:
    assert local['episode_guid'] == guid
    for revision in local['revisions']:
        cue_id = revision['cue_id']
        assert baseline[cue_id]['text'] == revision['baseline_text']
        assert text[cue_id] == revision['before']
        text[cue_id] = revision['after']
# Whisper.cpp gives search windows; the final Opus waveform supplies new timing.
cues = [dict(cue, text=text[cue['id']]) for cue in source['segments']]
review_input = dict(episode_guid=guid, source_transcript_sha256=hashlib.sha256(source_bytes).hexdigest(),
    listener_journal_sha256=hashlib.sha256(journal_bytes).hexdigest() if journal_bytes else None,
    listener_revision_count=len(local['revisions']) if local else 0,
    passages=[dict(id=cue['id'], text=cue['text']) for cue in cues])
(outputs / 'review-input.json').write_text(json.dumps(review_input, indent=2)+'\n')
import nltk
nltk.data.find('tokenizers/punkt_tab/english/')  # Fail before WhisperX can attempt a download.
model, metadata = whisperx.load_align_model(language_code='en', device='cpu', model_dir=str(project / 'work/whisperx-trial/models'))
audio = whisperx.load_audio(str(audio_path))
duration_ms = round(len(audio) / 16)
native = json.loads((outputs / 'probes/apple-decoded.json').read_text())['streams'][0]
ffmpeg = json.loads((outputs / 'probes/ffmpeg-decoded.json').read_text())['streams'][0]
assert abs(native['duration_ts'] - len(audio)) <= 1
assert abs(ffmpeg['duration_ts'] - len(audio)) <= 1
assert abs(json.loads((outputs / 'probes/avfoundation.json').read_text())['duration_s']*1000 - duration_ms) < 2
all_calls = []

def align_range(first, last):
    group = cues[first:last + 1]
    start = max(0, group[0]['start_ms'] / 1000 - 2)
    end = min(len(audio) / 16000, group[-1]['end_ms'] / 1000 + 2)
    joined = ' '.join(' '.join(cue['text'].split()) for cue in group)
    # Scope the adapter to this isolated worker call; do not edit site-packages
    # or globally replace NLTK's tokenizer. Passage text remains byte-for-byte.
    with patch.object(whisperx_alignment, 'nltk_load', return_value=AlignmentWindowTokenizer()):
        result = whisperx.align([dict(start=start, end=end, text=joined)], model,
            metadata, audio, 'cpu', interpolate_method='ignore', return_char_alignments=False)
    words = [word for segment in result['segments'] for word in segment.get('words', [])]
    if not aligned_words_match(joined, words):
        failure = outputs / f'word-mapping-failure-{group[0]["id"]}-{group[-1]["id"]}.json'
        failure.write_text(json.dumps(dict(first_id=group[0]['id'], last_id=group[-1]['id'],
            expected_words=joined.split(), actual_words=words, raw_result=result), indent=2)+'\n')
        raise AssertionError(f'Word mapping failed for {group[0]["id"]}–{group[-1]["id"]}; diagnostic: {failure.name}')
    mapped, index = {}, 0
    for cue in group:
        count = len(cue['text'].split())
        mapped[cue['id']] = words[index:index + count]
        index += count
    all_calls.append(dict(first_id=group[0]['id'], last_id=group[-1]['id'], result=result))
    return mapped

groups = []
for index, cue in enumerate(cues):
    if not groups or cue['end_ms'] - cues[groups[-1][0]]['start_ms'] > 25000:
        groups.append([])
    groups[-1].append(index)
aligned = {}
for number, group in enumerate(groups):
    result = align_range(max(0, group[0] - 2), min(len(cues) - 1, group[-1] + 2))
    for index in group:
        aligned[cues[index]['id']] = result[cues[index]['id']]
    print(f'Chunk {number+1}/{len(groups)}; passages {group[0]+1}–{group[-1]+1}', flush=True)

def bounds(words):
    timed = [w for w in words if 'start' in w and 'end' in w]
    if not timed:
        return None
    return round(min(w['start'] for w in timed)*1000), round(max(w['end'] for w in timed)*1000)

# Resolve neighbouring chunk disagreements from one shared acoustic alignment.
repairs = []
for iteration in range(2):
    conflicts = []
    for index in range(len(cues)-1):
        a, b = bounds(aligned[cues[index]['id']]), bounds(aligned[cues[index+1]['id']])
        if a and b and a[1] > b[0]: conflicts.append(index)
    if not conflicts: break
    for index in conflicts:
        result = align_range(max(0, index-2), min(len(cues)-1, index+3))
        for cue in cues[index:index+2]: aligned[cue['id']] = result[cue['id']]
        repairs.append(dict(iteration=iteration, pair=[cues[index]['id'], cues[index+1]['id']]))
    print(f'Boundary pass {iteration+1}: jointly realigned {len(conflicts)} pairs', flush=True)

records = []
for cue in cues:
    words = aligned[cue['id']]
    timed = [w for w in words if 'start' in w and 'end' in w]
    scores = [w['score'] for w in timed if 'score' in w]
    span = bounds(words)
    flags = []
    if span is None:
        span = cue['start_ms'], cue['end_ms']
        flags.append('No word timing; approximate Whisper timing retained for review.')
    if len(timed) < len(words): flags.append('Some words have no acoustic timing.')
    mean = statistics.mean(scores) if scores else 0
    if mean < 0.5: flags.append('Low acoustic alignment score; listening review recommended.')
    records.append(dict(id=cue['id'], source_start_ms=baseline[cue['id']]['start_ms'], source_end_ms=baseline[cue['id']]['end_ms'],
        baseline_text=baseline[cue['id']]['text'], aligned_text=cue['text'],
        start_ms=max(0, span[0]), end_ms=min(duration_ms, span[1]),
        mean_word_score=mean, review_flags=flags, words=words))

# One highlight cannot represent simultaneous speech. Any residual overlap gets
# an explicit shared display boundary; raw word spans remain available in output.
display_boundaries = []
for a, b in zip(records, records[1:]):
    if a['end_ms'] > b['start_ms']:
        boundary = round((a['end_ms'] + b['start_ms']) / 2)
        assert a['start_ms'] < boundary < b['end_ms'], 'Non-monotonic alignment requires review, not adoption.'
        display_boundaries.append(dict(left=a['id'], right=b['id'],
            raw_left_end_ms=a['end_ms'], raw_right_start_ms=b['start_ms'], display_boundary_ms=boundary))
        a['end_ms'] = b['start_ms'] = boundary
        a['review_flags'].append('Shared display boundary reconciles overlapping word timings.')
        b['review_flags'].append('Shared display boundary reconciles overlapping word timings.')

previous_end = 0
for original, record in zip(source['segments'], records):
    assert record['id'] == original['id']
    assert record['baseline_text'] == original['text']
    assert previous_end <= record['start_ms'] < record['end_ms'] <= duration_ms
    previous_end = record['end_ms']
assert source_path.read_bytes() == source_bytes
assert (journal_path.read_bytes() if journal_path.exists() else None) == journal_bytes
assert audio_path.read_bytes() == audio_bytes

key = json.loads((outputs / 'episode.json').read_text())['package_key']
document = dict(schema_version=1, episode_guid=guid, audio_identity='sha256:'+audio_hash,
    audio_asset=None if os.environ.get('EPISODE_RUN_ID') else f'assets/episodes/{key}/audio.opus', audio_file='audio.opus', edition_id=os.environ.get('EPISODE_RUN_ID'), audio_duration_ms=duration_ms,
    source_audio_sha256=source_audio_hash,
    source_transcript_sha256=hashlib.sha256(source_bytes).hexdigest(),
    method=f'WhisperX {importlib.metadata.version("whisperx")} CPU English wav2vec2 with neighbouring passage context and intact acoustic-window word mapping; measured against final Opus decode.',
    human_audio_checked=False, segments=[{k:v for k,v in row.items() if k!='words'} for row in records])
(outputs / 'alignment.json').write_text(json.dumps(document, indent=2)+'\n')
(outputs / 'word-alignment.json').write_text(json.dumps(records, indent=2)+'\n')
(outputs / 'boundary-repairs.json').write_text(json.dumps(dict(joint_realignments=repairs, shared_display_boundaries=display_boundaries), indent=2)+'\n')
(outputs / 'raw-chunks.json').write_text(json.dumps(all_calls, indent=2)+'\n')
summary = dict(passages=len(records), audio_identity=document['audio_identity'], audio_duration_ms=duration_ms,
    passages_with_flags=[r['id'] for r in records if r['review_flags']],
    missing_word_timing_passages=[r['id'] for r in records if any('No word timing' in flag for flag in r['review_flags'])],
    elapsed_seconds=round(time.perf_counter()-started,3), shared_boundaries=len(display_boundaries),
    joint_realignments=len(repairs), original_transcript_and_journal_unchanged=True,
    local_revisions_count=len(local['revisions']) if local else 0,
    preserved_original_ids_and_baseline_text=True, ordered_bounded_positive_cues=True)
(outputs / 'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
with (outputs / 'comparison.tsv').open('w',newline='') as file:
    columns=['id','source_start_ms','start_ms','source_end_ms','end_ms','mean_word_score','review_flags','aligned_text']
    writer=csv.DictWriter(file,fieldnames=columns,delimiter='\t',extrasaction='ignore')
    writer.writeheader()
    for row in records: writer.writerow(dict(row,review_flags='; '.join(row['review_flags'])))
print(json.dumps(summary,indent=2),flush=True)
PY
print -r -- "Full alignment saved in ${alignment_outputs}"

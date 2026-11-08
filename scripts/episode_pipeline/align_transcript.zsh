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
if [[ -f "${alignment_outputs}/alignment.log" ]]; then
  cp "${alignment_outputs}/alignment.log" "${alignment_outputs}/alignment-before-retry-$(date +%Y%m%dT%H%M%S)-$$.log"
fi
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
sys.path.insert(0, str(project / 'scripts/episode_pipeline/lib'))
from alignment_recovery import (AlignmentCache, atomic_json, word_bounds, recover_groups,
                                reconcile_display, MAX_DISPLAY_OVERLAP_MS,
                                capture_acoustic_result, select_cached_path)
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
model = metadata = None
model_path = project / 'work/whisperx-trial/models/wav2vec2_fairseq_base_ls960_asr_ls960.pth'
model_hash = hashlib.sha256(model_path.read_bytes()).hexdigest()
config = json.loads((outputs / 'config.json').read_text())
if model_hash != config['alignment_model_sha256']:
    raise ValueError('Alignment model changed; refusing to reuse this run.')
identity = dict(schema_version=1, episode_guid=guid,
    audio_sha256=audio_hash, baseline_sha256=hashlib.sha256(source_bytes).hexdigest(),
    journal_sha256=hashlib.sha256(journal_bytes).hexdigest() if journal_bytes else None,
    model_sha256=model_hash,
    versions={name: importlib.metadata.version(name) for name in ('whisperx', 'torch', 'torchaudio', 'numpy', 'transformers')},
    inference=dict(adapter='intact-acoustic-window-v1', device='cpu', threads=4,
                   padding_seconds=2, interpolate_method='ignore', return_char_alignments=False))
cache = AlignmentCache(outputs, identity)
atomic_json(outputs / 'alignment-validation.json', dict(state='in_progress', cache_namespace=cache.namespace))
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
    request = dict(first_id=group[0]['id'], last_id=group[-1]['id'], start=start, end=end,
                   passages=[dict(id=cue['id'], text=cue['text']) for cue in group])

    def compute():
        global model, metadata
        if model is None:
            model, metadata = whisperx.load_align_model(language_code='en', device='cpu',
                model_dir=str(project / 'work/whisperx-trial/models'))
        with patch.object(whisperx_alignment, 'nltk_load', return_value=AlignmentWindowTokenizer()):
            result = whisperx.align([dict(start=start, end=end, text=joined)], model,
                metadata, audio, 'cpu', interpolate_method='ignore', return_char_alignments=False)
        result = capture_acoustic_result(cache, request, result, group, outputs)
        words = [word for segment in result['segments'] for word in segment.get('words', [])]
        if not aligned_words_match(joined, words):
            failure = outputs / f'word-mapping-failure-{group[0]["id"]}-{group[-1]["id"]}.json'
            atomic_json(failure, dict(request=request, expected_words=joined.split(),
                                     actual_words=words, raw_result=result))
            raise ValueError(f'Word mapping failed for {group[0]["id"]}–{group[-1]["id"]}; diagnostic: {failure.name}')
        return result

    result, reused = cache.call(request, compute)
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
    all_calls.append(dict(first_id=group[0]['id'], last_id=group[-1]['id'], cached=reused, result=result))
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
    atomic_json(outputs / 'alignment-progress.json', dict(cache_namespace=cache.namespace,
        completed_chunks=number+1, total_chunks=len(groups), cache_hits=cache.hits, cache_misses=cache.misses,
        completed_passage_ids=[cue['id'] for cue in cues if cue['id'] in aligned],
        latest_chunk_passage_ids=[cues[index]['id'] for index in group]))
    print(f'Chunk {number+1}/{len(groups)}; passages {group[0]+1}–{group[-1]+1}; cache hits {cache.hits}', flush=True)

# Save connected conflict groups and replace the complete shared context window.
if select_cached_path(cues, aligned, duration_ms, cache, outputs):
    repairs = []
    print('Consistent acoustic path selected from saved calls; no group inference needed.', flush=True)
else:
    repairs = recover_groups(cues, aligned, duration_ms, align_range, outputs)
    select_cached_path(cues, aligned, duration_ms, cache, outputs)

selection = json.loads((outputs / 'alignment-alternative-selection.json').read_text())
alternative_changes = {row['passage_id'] for row in selection.get('changes', [])}
records = []
for cue in cues:
    words = aligned[cue['id']]
    timed = [w for w in words if 'start' in w and 'end' in w]
    scores = [w['score'] for w in timed if 'score' in w]
    span = word_bounds(words)
    flags = []
    if cue['id'] in alternative_changes:
        flags.append('Selected a consistent cached acoustic alternative; raw call provenance retained.')
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

# Persist evidence before validation so a failure cannot discard expensive work.
atomic_json(outputs / 'alignment-candidate.json', dict(cache_namespace=cache.namespace, segments=records))
atomic_json(outputs / 'raw-chunks.json', all_calls)
candidate_records = records
records, display_boundaries, problems = reconcile_display(records, duration_ms)
atomic_json(outputs / 'boundary-repairs.json', dict(joint_realignments=repairs,
    shared_display_boundaries=display_boundaries, maximum_display_overlap_ms=MAX_DISPLAY_OVERLAP_MS))
if problems:
    affected = sorted({pid for problem in problems for pid in problem['passage_ids']})
    failure = dict(state='failed', reason='Unresolved acoustic timing conflicts; no edition activated.',
        cache_namespace=cache.namespace, passage_ids=affected, problems=problems,
        passages=[row for row in candidate_records if row['id'] in affected],
        raw_candidate_file='alignment-candidate.json', checkpoints=str(cache.folder.relative_to(outputs)))
    atomic_json(outputs / 'alignment-failure.json', failure)
    review = ['# Alignment conflicts requiring review', '',
        'No new edition was activated. Raw words and completed acoustic calls are retained.', '',
        'Inspect the following passages in the retained audio before changing text or timings.', '']
    for row in failure['passages']:
        review.extend([f"## Passage {row['id']}", '', row['aligned_text'], '',
            f"Candidate interval: {row['start_ms']}–{row['end_ms']} ms. Mean acoustic word score: {row['mean_word_score']:.3f}.", '',
            f"Baseline interval: {row['source_start_ms']}–{row['source_end_ms']} ms.", ''])
    (outputs / 'alignment-failure.md').write_text('\n'.join(review)+'\n')
    atomic_json(outputs / 'alignment-validation.json', dict(state='failed', passage_ids=affected,
                                                         diagnostic='alignment-failure.json'))
    labels = ', '.join(map(str, affected[:12])) + ('…' if len(affected)>12 else '')
    raise ValueError(f'Alignment timing conflict in passages {labels}; inspect alignment-failure.json. Completed acoustic chunks are saved for resume.')

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
    joint_realignments=len(repairs), cached_alternatives_selected=len(alternative_changes), cache_hits=cache.hits, cache_misses=cache.misses,
    cache_namespace=cache.namespace, original_transcript_and_journal_unchanged=True,
    local_revisions_count=len(local['revisions']) if local else 0,
    preserved_original_ids_and_baseline_text=True, ordered_bounded_positive_cues=True)
(outputs / 'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
with (outputs / 'comparison.tsv').open('w',newline='') as file:
    columns=['id','source_start_ms','start_ms','source_end_ms','end_ms','mean_word_score','review_flags','aligned_text']
    writer=csv.DictWriter(file,fieldnames=columns,delimiter='\t',extrasaction='ignore')
    writer.writeheader()
    for row in records: writer.writerow(dict(row,review_flags='; '.join(row['review_flags'])))
atomic_json(outputs / 'alignment-validation.json', dict(state='passed', cache_namespace=cache.namespace,
                                                      ordered_bounded_positive_cues=True))
# Old diagnostics remain available but are explicitly superseded by this marker.
print(json.dumps(summary,indent=2),flush=True)
PY
print -r -- "Full alignment saved in ${alignment_outputs}"

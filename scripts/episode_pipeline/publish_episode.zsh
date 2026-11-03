#!/bin/zsh
set -euo pipefail
opus_outputs="${EPISODE_OUTPUTS:?Run scripts/prepare_episode.zsh}"
opus_project="${EPISODE_PROJECT:?}"
opus_python="${EPISODE_PYTHON:?}"
# WhisperX's Python environment supplies its alignment API and data libraries;
# every runnable processing entry point is a zsh script.
"$opus_python" - "$opus_project" "$opus_outputs" <<'PY'
from pathlib import Path
import copy, email.utils, hashlib, json, os, shutil, sys
from datetime import datetime, timezone
import yaml

project, outputs = map(Path, sys.argv[1:])
meta = json.loads((outputs / 'episode.json').read_text())
guid = meta['guid']
key = meta['package_key']
stage = Path(os.environ['EPISODE_WORK']) / 'episode'
destination = Path(os.environ.get('EPISODE_PACKAGE', str(project / 'flutter_app/assets/episodes' / key)))
audio_path = (destination if destination.exists() else stage) / 'audio.opus'
audio_hash = hashlib.sha256(audio_path.read_bytes()).hexdigest()
base_path = outputs / 'baseline.json'
base_bytes = base_path.read_bytes()
base = json.loads(base_bytes)
alignment_bytes = (outputs / 'alignment.json').read_bytes()
alignment = json.loads(alignment_bytes)
review_input = json.loads((outputs / 'review-input.json').read_text())
summary = json.loads((outputs / 'summary.json').read_text())
native = json.loads((outputs / 'probes/avfoundation.json').read_text())
assert native['playable'] and len(native['paused_native_seeks']) == 7
assert all(s['completed'] and abs(s['requested_s']-s['actual_s']) <= .05 for s in native['paused_native_seeks'])
assert alignment['audio_identity'] == 'sha256:' + audio_hash
assert alignment['source_transcript_sha256'] == hashlib.sha256(base_bytes).hexdigest() == review_input['source_transcript_sha256']
assert alignment['episode_guid'] == base['episode_guid'] == guid
passage_count = len(base['segments'])
assert passage_count > 0 and len(alignment['segments']) == passage_count
assert summary['ordered_bounded_positive_cues']
source_path = Path(os.environ.get('EPISODE_SOURCE', str(Path(os.environ['EPISODE_WORK']) / 'source.mp3')))
source_hash = hashlib.sha256(source_path.read_bytes()).hexdigest()
assert source_hash == alignment['source_audio_sha256']
journal_path = Path(os.environ['EPISODE_JOURNALS']) / (guid.encode().hex()+'.json')
journal_bytes = journal_path.read_bytes() if journal_path.exists() else None
assert (hashlib.sha256(journal_bytes).hexdigest() if journal_bytes else None) == review_input['listener_journal_sha256'], 'Journal changed during processing; rerun alignment before publishing.'

def write_json(path, data):
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False)+'\n')
config = json.loads((outputs/'config.json').read_text())
catalogue_path = outputs/'catalogue-snapshot.yaml'
# Legacy runs can still publish only if their live catalogue is unchanged.
if not catalogue_path.exists(): catalogue_path = project/'data/segments.yaml'
assert hashlib.sha256(catalogue_path.read_bytes()).hexdigest() == config['segments_catalogue_sha256'], 'Run catalogue snapshot changed or missing.'
if destination.exists():
    manifest = json.loads((destination/'episode.json').read_text())
    assert manifest['episode_guid'] == guid and manifest['audio']['sha256'] == audio_hash
    assert manifest['audio']['source_sha256'] == source_hash
    assert (destination/'transcript/baseline.json').read_bytes() == base_bytes
    assert (destination/'transcript/alignment.json').read_bytes() == alignment_bytes
    for artifact in manifest['artifacts']:
        payload = destination / artifact['file']
        assert payload.stat().st_size == artifact['byte_length']
        assert hashlib.sha256(payload.read_bytes()).hexdigest() == artifact['sha256']
    for relative, expected in config['existing_manifests'].items():
        existing_manifest = project / relative
        assert hashlib.sha256(existing_manifest.read_bytes()).hexdigest() == expected, 'Existing package changed during processing.'
        for artifact in json.loads(existing_manifest.read_text())['artifacts']:
            assert hashlib.sha256((existing_manifest.parent/artifact['file']).read_bytes()).hexdigest() == artifact['sha256']
else:
    transcript_dir = stage / 'transcript'
    transcript_dir.mkdir(exist_ok=True)
    (transcript_dir / 'baseline.json').write_bytes(base_bytes)
    (transcript_dir / 'alignment.json').write_bytes(alignment_bytes)
    shutil.copyfile(outputs / 'word-alignment.json', transcript_dir / 'words.json')
    listener = copy.deepcopy(base)
    listener['audio_identity'] = alignment['audio_identity']
    listener['alignment'] = {k:v for k,v in alignment.items() if k != 'segments'}
    listener['playback_sync_offset_ms'] = 0
    listener['review']['note'] += ' Timings measured against the final Opus recording with WhisperX; listening review still required for flagged passages.'
    listener['segments'] = []
    changes = {row['line']: row for row in listener['changes']}
    previous_end = 0
    for baseline, cue in zip(base['segments'], alignment['segments']):
        assert cue['id'] == baseline['id'] and cue['baseline_text'] == baseline['text']
        assert (cue['source_start_ms'],cue['source_end_ms']) == (baseline['start_ms'],baseline['end_ms'])
        assert previous_end <= cue['start_ms'] < cue['end_ms'] <= alignment['audio_duration_ms']
        previous_end = cue['end_ms']
        listener['segments'].append(dict(id=cue['id'], start_ms=cue['start_ms'], end_ms=cue['end_ms'],
            source_start_ms=cue['source_start_ms'],source_end_ms=cue['source_end_ms'],text=cue['aligned_text']))
        if cue['aligned_text'] != baseline['text']:
            changes[cue['id']] = dict(changes.get(cue['id'],{}),line=cue['id'],
                original_text=changes.get(cue['id'],{}).get('original_text',baseline['text']),
                text=cue['aligned_text'],local_correction=True)
        for flag in cue['review_flags']:
            listener['unresolved'].append(dict(lines=[cue['id']],reason='Timing: '+flag))
    listener['changes'] = list(changes.values())
    
    write_json(transcript_dir / 'listener.json', listener)
    (transcript_dir / 'transcript.txt').write_text('\n'.join(c['text'] for c in listener['segments'])+'\n')
    def stamp(ms, separator):
        return f'{ms//3600000:02}:{ms//60000%60:02}:{ms//1000%60:02}{separator}{ms%1000:03}'
    vtt, srt = ['WEBVTT\n'], []
    for index, cue in enumerate(listener['segments'],1):
        text = cue['text'].replace('\n',' ')
        escaped = text.replace('&','&amp;').replace('<','&lt;').replace('>','&gt;')
        vtt.append(f"{stamp(cue['start_ms'],'.')} --> {stamp(cue['end_ms'],'.')}\n{escaped}\n")
        srt.append(f"{index}\n{stamp(cue['start_ms'],',')} --> {stamp(cue['end_ms'],',')}\n{text}\n")
    (transcript_dir / 'transcript.vtt').write_text('\n'.join(vtt))
    (transcript_dir / 'transcript.srt').write_text('\n'.join(srt))
    
    catalogue = yaml.safe_load(catalogue_path.read_text())
    rows = [dict(row, source_index=i) for i,row in enumerate(catalogue['segments']) if row['guid'] == guid]
    assert rows and all(row['episode_title'] == rows[0]['episode_title'] for row in rows)
    write_json(stage / 'segments.json', dict(schema_version=1,episode_guid=guid,
        timing_note='Publisher-supplied section timestamps, not individually acoustic-verified.',segments=rows))
    published = email.utils.parsedate_to_datetime(meta['published_raw']).astimezone(timezone.utc).isoformat()
    provenance = dict(schema_version=1,episode_guid=guid,source_audio_sha256=source_hash,
        source_bytes=source_path.stat().st_size,source_url=rows[0].get('audio_url'),
        original_retained_in_package=False,input_recording='retained Opus' if config.get('reused_audio') else 'publisher download',original_disposal_status='Original not redownloaded; retained Opus used as input.' if config.get('reused_audio') else 'Retained outside this package pending device/listening acceptance.',
        source_transcript_sha256=hashlib.sha256(base_bytes).hexdigest(),
        review_input_sha256=hashlib.sha256((outputs / 'review-input.json').read_bytes()).hexdigest(),
        listener_revision_count=review_input['listener_revision_count'],listener_journal_sha256=review_input['listener_journal_sha256'],
        transcription=dict(tool='whisper.cpp',model=Path(config['model_path']).name,language='en',threads=8,
            binary_sha256=config['whisper_binary_sha256'],
            model_sha256=config['model_sha256'],
            prompt=config['prompt'], recognition_audio_identity=alignment['audio_identity'],
            raw_output_sha256=hashlib.sha256((outputs/'raw-transcript.json').read_bytes()).hexdigest(),
            human_reviewed=False,contextual_corrections_applied=False,api_used=False),
        encoder=dict(name='libopus',ffmpeg_version=config['ffmpeg_version'],channels=1,sample_rate=48000,target_bitrate=16000,
            vbr='constrained',application='audio',compression_level=10),
        alignment_method=alignment['method'],native_media_inspection=native,
        human_full_episode_audio_checked=False,ios_checked=False)
    write_json(stage / 'provenance.json', provenance)
    manifest = dict(schema_version=1,key=key,episode_guid=guid,
        metadata=dict(title=rows[0]['episode_title'],number=str(rows[0].get('episode_number')),
            published_at_utc=published,podcast_title=catalogue['podcast']['title'],source_url=rows[0].get('source_url')),
        audio=dict(file='audio.opus',codec='opus',sha256=audio_hash,identity='sha256:'+audio_hash,
            duration_ms=alignment['audio_duration_ms'],byte_length=audio_path.stat().st_size,target_bitrate=16000,
            source_sha256=source_hash),
        transcript=dict(reviewed_file='transcript/baseline.json',alignment_file='transcript/alignment.json',
            words_file='transcript/words.json',listener_file='transcript/listener.json',text_file='transcript/transcript.txt',
            vtt_file='transcript/transcript.vtt',srt_file='transcript/transcript.srt',passage_count=passage_count,
            passages_needing_timing_review=summary['passages_with_flags']),
        segments_file='segments.json',provenance_file='provenance.json',
        created_at_utc=datetime.now(timezone.utc).isoformat(),artifacts=[])
    for file in sorted(stage.rglob('*')):
        if file.is_file() and file.name != 'episode.json':
            manifest['artifacts'].append(dict(file=file.relative_to(stage).as_posix(),sha256=hashlib.sha256(file.read_bytes()).hexdigest(),byte_length=file.stat().st_size))
    write_json(stage / 'episode.json',manifest)
    for artifact in manifest['artifacts']:
        file = stage / artifact['file']
        assert file.is_file() and file.stat().st_size == artifact['byte_length']
        assert hashlib.sha256(file.read_bytes()).hexdigest() == artifact['sha256']
    assert base_path.read_bytes() == base_bytes
    assert (journal_path.read_bytes() if journal_path.exists() else None) == journal_bytes
    for relative, expected in config['existing_manifests'].items():
        existing_manifest = project / relative
        assert hashlib.sha256(existing_manifest.read_bytes()).hexdigest() == expected, 'Existing package changed during processing.'
        for artifact in json.loads(existing_manifest.read_text())['artifacts']:
            assert hashlib.sha256((existing_manifest.parent/artifact['file']).read_bytes()).hexdigest() == artifact['sha256']
    destination.parent.mkdir(parents=True, exist_ok=True)
    stage.rename(destination)
write_json(outputs / 'published-manifest.json',manifest)
result = dict(package_asset_directory=None if os.environ.get('EPISODE_RUN_ID') else 'assets/episodes/'+key,package_directory=str(destination),audio_sha256=audio_hash,
    source_bytes=source_path.stat().st_size,audio_bytes=manifest['audio']['byte_length'],
    audio_mib=manifest['audio']['byte_length']/1048576,
    reduction_percent=100*(1-manifest['audio']['byte_length']/source_path.stat().st_size),
    package_bytes=sum(a['byte_length'] for a in manifest['artifacts'])+(destination/'episode.json').stat().st_size,
    passages=passage_count,flags=summary['passages_with_flags'],local_revisions_preserved=review_input['listener_revision_count'],
    approximate_timing_passages=summary['missing_word_timing_passages'],existing_packages_unchanged=True,
    source_and_listener_journal_unchanged=True,artifact_checksums_verified=True,
    flutter_tests_run=False,flutter_analysis_run=False,ios_checked=False)
write_json(outputs / 'publication-summary.json',result)
docs = project / 'docs/transcripts'
docs.mkdir(parents=True, exist_ok=True)
stem = meta['export_stem']
def copy_export(source, target):
    data = source.read_bytes()
    if target.exists() and target.read_bytes() != data:
        raise SystemExit(f'Existing export differs; preserve/inspect it before retrying: {target}')
    if not target.exists():
        temp = target.with_suffix(target.suffix+'.tmp')
        temp.write_bytes(data)
        temp.replace(target)

for suffix in ['txt','vtt','srt']:
    copy_export(destination / f'transcript/transcript.{suffix}',docs / f'{stem}.{suffix}')
copy_export(destination/'transcript/listener.json',docs/f'{stem}.json')
for suffix in ['txt','srt','vtt','json']:
    copy_export(destination / ('transcript/listener.json' if suffix=='json' else f'transcript/transcript.{suffix}'),outputs/f'{stem}-aligned.{suffix}')
print(json.dumps(result,indent=2))
PY

#!/bin/zsh
set -euo pipefail
"${EPISODE_PYTHON:?Run scripts/prepare_episode.zsh}" - "$@" <<'PY'
from pathlib import Path
from datetime import datetime,timezone
import hashlib,json,os,sys
outputs=Path(os.environ['EPISODE_OUTPUTS']); project=Path(os.environ['EPISODE_PROJECT']); work=Path(os.environ['EPISODE_WORK'])
meta=json.loads((outputs/'episode.json').read_text()); package=Path(os.environ.get('EPISODE_PACKAGE', str(project/'flutter_app/assets/episodes'/meta['package_key'])))

def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def atomic(path,data):
    temp=path.with_suffix('.tmp');temp.write_text(json.dumps(data,indent=2)+'\n');temp.replace(path)
def payload_path(relative):
    path=package/relative
    if not path.resolve().is_relative_to(package.resolve()): raise SystemExit('Unsafe manifest path.')
    return path

action=sys.argv[1]
if action in ['save','verify']:
    checkpoint=outputs/'checkpoints'/f'{sys.argv[2]}.json'
    if action=='save':
        artifacts={str(Path(name)):digest(Path(name)) for name in sys.argv[3:]}
        if not artifacts: raise SystemExit('Empty checkpoint refused.')
        atomic(checkpoint,dict(created_at_utc=datetime.now(timezone.utc).isoformat(),artifacts=artifacts))
    else:
        for name,expected in json.loads(checkpoint.read_text())['artifacts'].items():
            path=Path(name)
            # Atomic publication moves staging into the final package. A crash
            # after rename must still be resumable, with the exact same bytes.
            if not path.exists() and path.is_relative_to(work/'episode'):
                path=package/path.relative_to(work/'episode')
            if not path.is_file() or digest(path)!=expected: raise SystemExit(f'Checkpoint changed/missing: {name}. Refusing mixed output.')
elif action=='verify-package':
    manifest=json.loads((package/'episode.json').read_text()); saved=json.loads((outputs/'published-manifest.json').read_text())
    if manifest!=saved or manifest['episode_guid']!=meta['guid']: raise SystemExit('Published edition differs from this run.')
    for artifact in manifest['artifacts']:
        path=payload_path(artifact['file'])
        if not path.is_file() or path.stat().st_size!=artifact['byte_length'] or digest(path)!=artifact['sha256']: raise SystemExit(f'Published artifact changed: {path}')
    for suffix in ['txt','json','srt','vtt']:
        canonical=package/('transcript/listener.json' if suffix=='json' else f'transcript/transcript.{suffix}')
        for exported in [outputs/f"{meta['export_stem']}-aligned.{suffix}",project/'docs/transcripts'/f"{meta['export_stem']}.{suffix}"]:
            if not exported.is_file() or digest(exported)!=digest(canonical): raise SystemExit(f'Export changed/missing: {exported}; inspect before resuming.')
    print('Published package and transcript export hashes verified.')
elif action=='report':
    summary=json.loads((outputs/'publication-summary.json').read_text()); alignment=json.loads((outputs/'alignment.json').read_text())
    registered=(outputs/'registration.json').exists(); disposed=(outputs/'source-disposal.json').exists()
    text=f'''# Episode {meta['episode_number']} — {meta['title']}

Generation completed. Machine transcribed; not reviewed.

- Passages: {summary['passages']:,}.
- Input recording bytes: {summary['source_bytes']:,}.
- Opus bytes: {summary['audio_bytes']:,} ({summary['audio_mib']:.1f} MiB).
- Reduction: {summary['reduction_percent']:.2f}%.
- Audio SHA-256: {summary['audio_sha256']}.
- App registered by this run: {registered}; rebuild required after registration.
- Original explicitly discarded: {disposed}.
- Package: {package}
- Listener transcript: {project/'docs/transcripts'/meta['export_stem']}.txt/json/srt/vtt

Raw recognition is raw-transcript.txt/json/srt/vtt. Both recognition and WhisperX
alignment used the retained Opus waveform. Alignment preserves baseline text and
original revision references. TXT contains one passage per line (passage = line).
The manifest lists checksums; raw chunks, word scores and provenance are retained.
Input recording stays in ignored work until explicit disposal. A retranscription
may use retained Opus rather than an original publisher download.

## Listening review

Scientific/person/place names remain unreviewed. Complete timing coverage does
not certify accuracy. Review flagged passages below plus start/middle/end playback,
forward/back skips, highlighting, search, editing/resume and persisted Nudge.
Repeat on iOS; record date, environment, tester and results before source disposal.
Native inspection performed seven paused seeks, never audible playback.

| Passage / TXT line | Start ms | Timing review reason |
| --- | --- | --- |
'''
    for cue in alignment['segments']:
        if cue['review_flags']: text+=f"| {cue['id']} | {cue['start_ms']} | {'; '.join(cue['review_flags'])} |\n"
    if not summary['flags']: text+='| — | — | No automatic acoustic flags; wording still unreviewed. |\n'
    text+='''
## Manual Flutter acceptance

From flutter_app in zsh, after registration (default; --no-register opts out):

```zsh
flutter analyze
flutter test test/data/episode_package_repository_test.dart test/data/episode_package_manifest_test.dart
flutter run -d macos
```

The pipeline does not run Flutter tests, analysis, builds, apps or Git actions.
It checks hashes, positive ordered bounded timings and Apple/FFmpeg sample counts.
App acceptance and contextual/listening review remain pending.
'''
    index_summary=package/'indexing/summary.json'
    if index_summary.exists():
        info=json.loads(index_summary.read_text())
        text+='\n## Local index\n\n'
        text+=f"- Method: {info['method']}; model: {info['model']}.\n"
        text+=f"- Entries: {info['entries']}; categories: {info['categories']}.\n"
        text+=f"- Time: {info['seconds']} seconds; paid API calls: 0.\n"
        text+=f"- Evidence edition: {info['edition']}; passages: {info['passages']}.\n"
        text+=f"- Index: {package/'indexing/index.json'}.\n"
        text+=f"- Unidentified reference groups: {info.get('unidentified_reference_mentions', 0)} (review material, not identified publications).\n"
        text+='- Suggested names and reference cues require review; bibliography/author links are not verified.\n'
    else:
        text+='\nLocal index: not generated by this legacy run.\n'
    enrichment=package/'indexing/summary.json'
    if enrichment.exists():
        final=json.loads(enrichment.read_text());result=final.get('external_enrichment')
        text+='\n## Final index revision\n\n- Index SHA-256: '+final['index_sha256']+'\n'
        if final.get('refinement'):text+='- ChatGPT refinement: '+json.dumps(final['refinement'])+'\n'
        if result:
            text+='- External enrichment: '+json.dumps(result,ensure_ascii=False)+'\n'
            text+='- Clear matches were applied automatically. Unresolved identities, stale evidence and source outages are listed separately.\n'
            if result.get('warnings'):text+='- Source data was incomplete; the usable index is retained. Retry enrichment without transcription or ChatGPT using scripts/enrich_episode_index.zsh --retry.\n'
        else:text+='- External enrichment deferred to preparation worker, or not generated by this older run.\n'
    (outputs/'README.md').write_text(text)
else: raise SystemExit('Unknown checkpoint action.')
PY

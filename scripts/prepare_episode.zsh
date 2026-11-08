#!/bin/zsh
# Prepare one catalogue episode. No Bash entry points or paid transcription API.
set -euo pipefail
unset PYTHONOPTIMIZE
zmodload zsh/datetime
pipeline_scripts="${0:A:h}"
export EPISODE_PROJECT="${pipeline_scripts:h}"
export NLTK_DATA="${EPISODE_PROJECT}/work/whisperx-trial/nltk_data"
pipeline_helpers="${pipeline_scripts}/episode_pipeline"
export EPISODE_PYTHON="${EPISODE_PYTHON:-${EPISODE_PROJECT}/work/whisperx-trial/venv/bin/python}"
export EPISODE_JOURNALS="${EPISODE_JOURNALS:-${HOME}/Library/Containers/com.example.commonDescentListing/Data/Library/Application Support/com.example.commonDescentListing/transcript-edits}"
pipeline_number=''
pipeline_resume=0
pipeline_register=1
pipeline_discard=0
pipeline_enrichment_offline=0
pipeline_enrichment_retry=0
pipeline_model="${WHISPER_MODEL:-}"
pipeline_prompt=''
usage() {
  cat <<'HELP'
Usage: zsh scripts/prepare_episode.zsh EPISODE [options]
  --model PATH         Override medium.en (or use WHISPER_MODEL).
  --prompt TEXT        Recognition context; defaults to podcast and episode title.
  --resume             Resume this pipeline's unchanged configuration/checkpoints.
  --register           Register package/assets in Flutter (default).
  --no-register        Prepare the package without changing app registration.
  --offline-enrichment Use cached external sources only; missing data is reported.
  --retry-enrichment   Retry incomplete lookups when resuming this run.
  --discard-original   Separate operation: delete this run's source after acceptance.
  --help               Show usage without processing.

Outputs: outputs/episodes/<stable-key>/ and docs/transcripts/.
Default: audio preparation, transcription/alignment, local indexing, external enrichment, report.
Local indexing requires work/local-index-benchmark/venv and its cached GLiNER model.
Scratch/source: work/episode-pipeline/<stable-key>/ (ignored by Git).
Requires macOS, ffmpeg/ffprobe, whisper-cli, jq, Swift/afconvert, and an existing
WhisperX Python environment with PyYAML, certifi, torch and cached English model.
No automatic dependency/model installation, Flutter run/build/test or Git action.
Do not remove a processing lock unless its recorded process has stopped.
HELP
}
while (( $# )); do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --resume) pipeline_resume=1; shift ;;
    --register) pipeline_register=1; shift ;;
    --no-register) pipeline_register=0; shift ;;
    --discard-original) pipeline_discard=1; shift ;;
    --offline-enrichment) pipeline_enrichment_offline=1; shift ;;
    --retry-enrichment) pipeline_enrichment_retry=1; shift ;;
    --model|--prompt)
      (( $# >= 2 )) || { print -u2 "Missing value for $1"; exit 2; }
      if [[ "$1" == --model ]]; then pipeline_model="$2"; else pipeline_prompt="$2"; fi
      shift 2 ;;
    -*) print -u2 "Unknown option: $1"; exit 2 ;;
    *) [[ -z "$pipeline_number" ]] || { print -u2 'Supply exactly one episode number.'; exit 2; }
       pipeline_number="$1"; shift ;;
  esac
done
[[ -n "$pipeline_number" ]] || { usage; exit 2; }
[[ -x "$EPISODE_PYTHON" ]] || { print -u2 "WhisperX Python environment missing: $EPISODE_PYTHON"; exit 2; }
# Catalogue identity is resolved before any download. Numbers may be fractional.
pipeline_key="$("$EPISODE_PYTHON" - "$EPISODE_PROJECT" "$pipeline_number" <<'PY'
from pathlib import Path
from decimal import Decimal, InvalidOperation
import hashlib,re,sys,yaml
try: number=Decimal(sys.argv[2])
except InvalidOperation: raise SystemExit('Invalid episode number.')
rows=yaml.safe_load((Path(sys.argv[1])/'data/episodes.yaml').read_text())['episodes']
def matches(row):
    try: return Decimal(str(row.get('episode_number'))) == number
    except InvalidOperation: return False
rows=[row for row in rows if matches(row)]
if len(rows)!=1: raise SystemExit(f'Expected one matching episode; found {len(rows)}.')
guid=rows[0]['guid']; key=guid.rsplit('-',1)[-1]
if not re.fullmatch(r'[A-Za-z0-9_-]{8,100}',key): key=hashlib.sha256(guid.encode()).hexdigest()[:32]
print(key)
PY
)"
pipeline_run="${EPISODE_RUN_ID:-}"
if [[ -n "$pipeline_run" ]]; then
  [[ "$pipeline_run" =~ ^[a-zA-Z0-9_-]+$ ]] || { print -u2 'Invalid run ID.'; exit 2; }
fi
export EPISODE_OUTPUTS="${EPISODE_PROJECT}/outputs/episodes/${pipeline_key}${pipeline_run:+/runs/${pipeline_run}}"
export EPISODE_WORK="${EPISODE_PROJECT}/work/episode-pipeline/${pipeline_key}${pipeline_run:+/runs/${pipeline_run}}"
export EPISODE_PACKAGE="${EPISODE_PACKAGE:-${EPISODE_PROJECT}/flutter_app/assets/episodes/${pipeline_key}}"
pipeline_package="$EPISODE_PACKAGE"
export EPISODE_SOURCE="${EPISODE_WORK}/source.mp3"
if [[ -n "${EPISODE_REUSE_AUDIO:-}" ]]; then export EPISODE_SOURCE="${EPISODE_WORK}/source.opus"; fi
if [[ -n "$pipeline_run" ]]; then pipeline_register=0; fi
mkdir -p "$EPISODE_OUTPUTS" "$EPISODE_WORK"
pipeline_lock="${EPISODE_WORK}/.processing-lock"
mkdir "$pipeline_lock" 2>/dev/null || {
  print -u2 "Episode is locked. Inspect ${pipeline_lock}/owner.txt before removing a stale lock."; exit 2
}
print -r -- "pid=$$ host=$(hostname) started=$(date -u +%FT%TZ)" > "${pipeline_lock}/owner.txt"
trap 'rm -f -- "${pipeline_lock}/owner.txt"; rmdir -- "$pipeline_lock"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if (( pipeline_discard )); then
  [[ -f "${EPISODE_OUTPUTS}/checkpoints/publish.json" ]] || {
    print -u2 'Only a successfully published pipeline run can discard its source.'; exit 2
  }
  /bin/zsh "${pipeline_helpers}/checkpoint.zsh" verify-package
  "$EPISODE_PYTHON" - "$EPISODE_WORK" "$EPISODE_OUTPUTS" <<'PY'
from pathlib import Path
from datetime import datetime,timezone
import hashlib,json,os,sys
work,outputs=map(Path,sys.argv[1:]); source=Path(os.environ['EPISODE_SOURCE'])
expected=(outputs/'source-checksum.txt').read_text().split()[0]
if source.exists():
    if hashlib.sha256(source.read_bytes()).hexdigest()!=expected: raise SystemExit('Source changed; refusing deletion.')
    source.unlink()
(outputs/'source-disposal.json').write_text(json.dumps(dict(discarded_at_utc=datetime.now(timezone.utc).isoformat(),sha256=expected,source_url=json.loads((outputs/'episode.json').read_text())['audio_url'],note='Explicit --discard-original requested; original is not in the listener package.'),indent=2)+'\n')
print('Original discarded. Compressed audio and transcription provenance retained.')
PY
  /bin/zsh "${pipeline_helpers}/checkpoint.zsh" report
  exit 0
fi
/bin/zsh "${pipeline_scripts}/index_episode_local.zsh" --check
for pipeline_tool in ffmpeg ffprobe whisper-cli jq shasum swift afconvert curl; do
  command -v "$pipeline_tool" >/dev/null || { print -u2 "Missing required tool: $pipeline_tool"; exit 2; }
done
[[ "$(uname -s)" == Darwin ]] || { print -u2 'Native media inspection currently requires macOS.'; exit 2; }
"$EPISODE_PYTHON" -c 'import yaml,certifi,torch,whisperx'
export PIPELINE_MODEL="$pipeline_model" PIPELINE_PROMPT="$pipeline_prompt" PIPELINE_RESUME="$pipeline_resume"
"$EPISODE_PYTHON" - "$EPISODE_PROJECT" "$EPISODE_OUTPUTS" "$pipeline_number" "$pipeline_key" <<'PY'
from pathlib import Path
from decimal import Decimal, InvalidOperation
import hashlib,importlib.metadata,json,nltk,os,re,shutil,subprocess,sys,yaml
project,outputs=map(Path,sys.argv[1:3]); number=Decimal(sys.argv[3]); key=sys.argv[4]
saved=outputs/'config.json'
if saved.exists() and os.environ['PIPELINE_RESUME']!='1': raise SystemExit('Run state exists; use --resume. Existing editions are never implicitly replaced.')
if not saved.exists() and os.environ['PIPELINE_RESUME']=='1': raise SystemExit('No pipeline run to resume.')
old=json.loads(saved.read_text()) if saved.exists() else None
if Path(os.environ['EPISODE_PACKAGE']).exists() and not old: raise SystemExit('This episode already has a published package. No download or overwrite performed.')
def matches(row):
    try: return Decimal(str(row.get('episode_number'))) == number
    except InvalidOperation: return False
rows=yaml.safe_load((project/'data/episodes.yaml').read_text())['episodes']; selected=[r for r in rows if matches(r)]
if len(selected)!=1: raise SystemExit('Episode identity is ambiguous.')
catalogue_snapshot=outputs/'catalogue-snapshot.yaml'
if not catalogue_snapshot.exists():
    catalogue_bytes=(project/'data/segments.yaml').read_bytes()
    if old and hashlib.sha256(catalogue_bytes).hexdigest()!=old['segments_catalogue_sha256']:
        raise SystemExit('Original catalogue snapshot missing and live catalogue changed. Preserve this run for explicit recovery.')
    catalogue_snapshot.write_bytes(catalogue_bytes)
meta=dict(selected[0]); meta['package_key']=key
if not meta.get('audio_url','').startswith('https://'): raise SystemExit('Missing HTTPS audio URL.')
slug=re.sub('[^a-z0-9]+','-',meta['title'].lower()).strip('-')[:70]
meta['export_stem']='episode-'+str(meta['episode_number']).zfill(3).replace('.','-')+'-'+slug+('-'+os.environ['EPISODE_RUN_ID'] if os.environ.get('EPISODE_RUN_ID') else '')
prompt=os.environ['PIPELINE_PROMPT'] or (old['prompt'] if old else 'The Common Descent Podcast. '+meta['title']+'.')
model=Path(os.environ['PIPELINE_MODEL'] or (old['model_path'] if old else project/'work/whisper/models/ggml-medium.en.bin')).expanduser().resolve()
if not model.is_file(): raise SystemExit('Model missing. Default is work/whisper/models/ggml-medium.en.bin; supply --model PATH or WHISPER_MODEL to override.')
model_hash=hashlib.sha256(model.read_bytes()).hexdigest()
binary=Path(shutil.which('whisper-cli')).resolve()
alignment_model=project/'work/whisperx-trial/models/wav2vec2_fairseq_base_ls960_asr_ls960.pth'
if not alignment_model.is_file(): raise SystemExit('Cached WhisperX English alignment model missing; install it explicitly before processing.')
try: nltk.data.find('tokenizers/punkt_tab/english/')
except LookupError: raise SystemExit('Cached NLTK punkt_tab English data missing; install it explicitly before processing.')
versions={name:importlib.metadata.version(name) for name in ['whisperx','torch','PyYAML']}
helper_files=[project/'scripts/prepare_episode.zsh',*sorted((project/'scripts/episode_pipeline').glob('*.zsh')),*sorted((project/'scripts/episode_pipeline/lib').glob('*.py'))]
code={str(f.relative_to(project)):hashlib.sha256(f.read_bytes()).hexdigest() for f in helper_files}
config=dict(schema_version=1,episode_guid=meta['guid'],metadata=meta,model_path=str(model),model_sha256=model_hash,
    alignment_model_sha256=hashlib.sha256(alignment_model.read_bytes()).hexdigest(),
    segments_catalogue_sha256=hashlib.sha256(catalogue_snapshot.read_bytes()).hexdigest(),
    package_directory=os.environ['EPISODE_PACKAGE'],reused_audio=os.environ.get('EPISODE_REUSE_AUDIO'),prompt=prompt,whisper_binary_sha256=hashlib.sha256(binary.read_bytes()).hexdigest(),versions=versions,
    ffmpeg_version=subprocess.check_output(['ffmpeg','-version'],text=True).splitlines()[0],
    python=str(Path(os.environ['EPISODE_PYTHON']).resolve()),journal_root=os.environ['EPISODE_JOURNALS'],scripts=code,
    existing_manifests=old['existing_manifests'] if old else {str(f.relative_to(project)):hashlib.sha256(f.read_bytes()).hexdigest() for f in sorted((project/'flutter_app/assets/episodes').glob('*/episode.json'))})
if old and config!=old:
    # Explicit, audited migrations for known predecessor revisions only.
    # Completed alignment/publication is never reinterpreted by a new aligner.
    legacy={'scripts/prepare_episode.zsh': 'b435783b01bd2d75c5fbe77602857c365db88b643faab7434faac53b71fe686f', 'scripts/episode_pipeline/build_baseline.zsh': 'ce4fc1ba6d8d500df3517f63677221b3d1c6b87fc882319ecb774cd8059f14cb'}
    alignment_legacy={'scripts/prepare_episode.zsh': '46a4caa9a0f8c6346a44dc74dba81ab5a993951ce49c0f1f835c7df82b4500f9', 'scripts/episode_pipeline/align_transcript.zsh': 'dadfadac7822e79544bdfefb6f5dfbd8f79a6b9c36f1f2b8e1fe61b7c8d86ee2'}
    numeric_legacy={'scripts/prepare_episode.zsh': 'ff7dd92ad0ad00fc3f83f9177a108f701902139ed2d1cd377f61128894ec8410', 'scripts/episode_pipeline/align_transcript.zsh': '2e34c19710a5f4ddf5180af37feb3be388e786e135ae841c51c5f960489e80fc', 'scripts/episode_pipeline/lib/alignment_recovery.py': '5d4736c4a65e955a7bd9cbe2740dbaf2e6233494799589ac31191d2c05454196'}
    alternatives_legacy={'scripts/prepare_episode.zsh': '680cd831326e2ff70beebbe273f1bc6a847bd181884aa74e36a92f517e714f06', 'scripts/episode_pipeline/align_transcript.zsh': '4a1562eb872ac368d21ddd52a238088c2b91840016f2f6a3d4d46b5a69bff04e', 'scripts/episode_pipeline/lib/alignment_recovery.py': '07de600b56a2ff503c112837befec3811ca21f816413926760f49a3c001595f2'}
    changed={name for name in set(old['scripts'])|set(code) if old['scripts'].get(name)!=code.get(name)}
    alignment_allowed=set(alignment_legacy)|{'scripts/episode_pipeline/lib/alignment_recovery.py'}
    baseline_allowed=set(legacy)|alignment_allowed|{'scripts/episode_pipeline/lib/baseline_timing.py'}
    same_inputs={k:v for k,v in config.items() if k!='scripts'}=={k:v for k,v in old.items() if k!='scripts'}
    baseline_migration=changed<=baseline_allowed and all(old['scripts'].get(k)==v for k,v in legacy.items()) and old['scripts'].get('scripts/episode_pipeline/align_transcript.zsh')==alignment_legacy['scripts/episode_pipeline/align_transcript.zsh'] and not (outputs/'checkpoints/baseline.json').exists()
    alignment_migration=changed<=alignment_allowed and all(old['scripts'].get(k)==v for k,v in alignment_legacy.items()) and (outputs/'checkpoints/baseline.json').exists()
    numeric_migration=changed<=set(numeric_legacy) and all(old['scripts'].get(k)==v for k,v in numeric_legacy.items()) and (outputs/'checkpoints/baseline.json').exists()
    alternatives_migration=changed<=set(alternatives_legacy) and all(old['scripts'].get(k)==v for k,v in alternatives_legacy.items()) and (outputs/'checkpoints/baseline.json').exists()
    migrate=same_inputs and (baseline_migration or alignment_migration or numeric_migration or alternatives_migration) and not any((outputs/'checkpoints'/name).exists() for name in ('align.json','publish.json'))
    if not migrate: raise SystemExit('Configuration, catalogue, model, tools or pipeline changed. Refusing to mix editions; inspect/archive this run explicitly.')
    for checkpoint in sorted((outputs/'checkpoints').glob('*.json')):
        for name,expected in json.loads(checkpoint.read_text())['artifacts'].items():
            artifact=Path(name)
            if not artifact.is_file() or hashlib.sha256(artifact.read_bytes()).hexdigest()!=expected:
                raise SystemExit(f'Checkpoint changed/missing: {name}. Recovery refused before migrating configuration.')
    reason='Consistent cached acoustic path selection' if alternatives_migration else 'Acoustic numeric normalization and pre-validation evidence' if numeric_migration else 'Alignment checkpoint/group recovery' if alignment_migration else 'Baseline timing and alignment recovery'
    history=outputs/('recovery-migration-'+hashlib.sha256(json.dumps(code,sort_keys=True).encode()).hexdigest()[:12]+'.json')
    if not history.exists(): history.write_text(json.dumps(dict(previous_config=old,new_scripts=code,reason=reason+'; inputs unchanged and completed checkpoints verified before migration.'),indent=2)+'\n')
    old=config
    temp=saved.with_suffix('.recovery.tmp');temp.write_text(json.dumps(config,indent=2)+'\n');temp.replace(saved)
for target,data in [(outputs/'episode.json',meta),(saved,config)]:
    text=json.dumps(data,indent=2)+'\n'
    if target.exists() and target.read_text()!=text: raise SystemExit(f'Unexpected changed metadata: {target}')
    if not target.exists():
        temp=target.with_suffix('.tmp'); temp.write_text(text); temp.replace(target)
print('Preparing Episode '+str(meta['episode_number'])+' — '+meta['title'])
PY
mkdir -p "${EPISODE_OUTPUTS}/probes" "${EPISODE_OUTPUTS}/checkpoints"
# Completed runs verify their published edition, without needing deleted scratch.
if [[ -f "${EPISODE_OUTPUTS}/checkpoints/publish.json" ]]; then
  /bin/zsh "${pipeline_helpers}/checkpoint.zsh" verify-package
else
  run_stage() {
    local stage_name="$1" stage_function="$2"
    shift 2
    if [[ -f "${EPISODE_OUTPUTS}/checkpoints/${stage_name}.json" ]]; then
      /bin/zsh "${pipeline_helpers}/checkpoint.zsh" verify "$stage_name"
      print -r -- "Resume: ${stage_name} artifacts unchanged."
    else
      print -r -- "PREP_STAGE ${stage_name}"
      print -r -- "Running ${stage_name}…"
      "$stage_function"
      /bin/zsh "${pipeline_helpers}/checkpoint.zsh" save "$stage_name" "$@"
      print -r -- "PREP_STAGE_DONE ${stage_name}"
    fi
  }
  capture() {
    local source_url="$(jq -r '.audio_url' "${EPISODE_OUTPUTS}/episode.json")"
    if [[ ! -f "${EPISODE_SOURCE}" && -n "${EPISODE_REUSE_AUDIO:-}" ]]; then
      cp "$EPISODE_REUSE_AUDIO" "${EPISODE_SOURCE}"
    fi
    if [[ ! -f "${EPISODE_SOURCE}" ]]; then
      curl --fail --location --retry 2 --connect-timeout 30 --max-time 1800 \
        --dump-header "${EPISODE_OUTPUTS}/probes/download-headers.txt" \
        "$source_url" -o "${EPISODE_SOURCE}.part"
      mv "${EPISODE_SOURCE}.part" "${EPISODE_SOURCE}"
    fi
    shasum -a 256 "${EPISODE_SOURCE}" > "${EPISODE_OUTPUTS}/source-checksum.txt"
    ffprobe -v error -show_format -show_streams -of json "${EPISODE_SOURCE}" > "${EPISODE_OUTPUTS}/probes/source.json"
  }
  encode() {
    mkdir -p "${EPISODE_WORK}/episode"
    [[ ! -e "${pipeline_package}/audio.opus" ]] || { print -u2 'Published audio exists before encode completed.'; return 1; }
    local title="$(jq -r '.title' "${EPISODE_OUTPUTS}/episode.json")"
    if [[ -n "${EPISODE_REUSE_AUDIO:-}" ]]; then
      cp "${EPISODE_SOURCE}" "${EPISODE_WORK}/episode/audio.part.opus"
    else
    ffmpeg -hide_banner -nostdin -loglevel error -y -i "${EPISODE_SOURCE}" \
      -progress pipe:1 -stats_period 0.5 -map 0:a:0 -map_metadata -1 -ac 1 -ar 48000 -c:a libopus -b:a 16k \
      -vbr constrained -application audio -compression_level 10 -metadata "title=${title}" \
      -metadata artist='The Common Descent Podcast' -metadata genre=Podcast "${EPISODE_WORK}/episode/audio.part.opus"
    fi
    mv "${EPISODE_WORK}/episode/audio.part.opus" "${EPISODE_WORK}/episode/audio.opus"
    ffprobe -v error -show_format -show_streams -of json "${EPISODE_WORK}/episode/audio.opus" > "${EPISODE_OUTPUTS}/probes/opus.json"
  }
  inspect_audio() {
    ffmpeg -hide_banner -nostdin -loglevel error -y -i "${EPISODE_WORK}/episode/audio.opus" -ar 16000 -ac 1 -c:a pcm_s16le "${EPISODE_WORK}/opus-ffmpeg.wav"
    rm -f -- "${EPISODE_WORK}/opus-apple.wav"
    /usr/bin/afconvert -f WAVE -d LEI16@16000 "${EPISODE_WORK}/episode/audio.opus" "${EPISODE_WORK}/opus-apple.wav"
    ffprobe -v error -show_streams -of json "${EPISODE_WORK}/opus-ffmpeg.wav" > "${EPISODE_OUTPUTS}/probes/ffmpeg-decoded.json"
    ffprobe -v error -show_streams -of json "${EPISODE_WORK}/opus-apple.wav" > "${EPISODE_OUTPUTS}/probes/apple-decoded.json"
    /bin/zsh "${pipeline_helpers}/inspect_apple_audio.zsh" "${EPISODE_WORK}/episode/audio.opus" > "${EPISODE_OUTPUTS}/probes/avfoundation.json"
  }
  transcribe() {
    # Recreate PCM from fingerprinted Opus, never trust an interrupted cache.
    ffmpeg -hide_banner -nostdin -loglevel error -y -i "${EPISODE_WORK}/episode/audio.opus" -ar 16000 -ac 1 -c:a pcm_s16le "${EPISODE_WORK}/opus-ffmpeg.wav"
    local started="$EPOCHREALTIME"
    local model="$(jq -r '.model_path' "${EPISODE_OUTPUTS}/config.json")"
    local prompt="$(jq -r '.prompt' "${EPISODE_OUTPUTS}/config.json")"
    mkdir -p "${EPISODE_WORK}/recognition"
    whisper-cli -m "$model" -f "${EPISODE_WORK}/opus-ffmpeg.wav" -l en -t 8 --prompt "$prompt" \
      -otxt -ovtt -osrt -oj -pp -of "${EPISODE_WORK}/recognition/raw-transcript" > "${EPISODE_OUTPUTS}/transcription.log" 2>&1
    for suffix in txt json vtt srt; do
      cp "${EPISODE_WORK}/recognition/raw-transcript.${suffix}" "${EPISODE_OUTPUTS}/raw-transcript.${suffix}"
    done
    print -r -- "elapsed_seconds=$((EPOCHREALTIME - started))" > "${EPISODE_OUTPUTS}/run-metrics.txt"
  }
  baseline() { /bin/zsh "${pipeline_helpers}/build_baseline.zsh"; }
  align() { /bin/zsh "${pipeline_helpers}/align_transcript.zsh"; }
  publish() { /bin/zsh "${pipeline_helpers}/publish_episode.zsh"; }
  run_stage capture capture "${EPISODE_SOURCE}" "${EPISODE_OUTPUTS}/source-checksum.txt" "${EPISODE_OUTPUTS}/probes/source.json"
  run_stage encode encode "${EPISODE_WORK}/episode/audio.opus" "${EPISODE_OUTPUTS}/probes/opus.json"
  run_stage inspect inspect_audio "${EPISODE_OUTPUTS}/probes/avfoundation.json" "${EPISODE_OUTPUTS}/probes/apple-decoded.json" "${EPISODE_OUTPUTS}/probes/ffmpeg-decoded.json"
  run_stage transcribe transcribe "${EPISODE_OUTPUTS}"/raw-transcript.{txt,json,srt,vtt} "${EPISODE_OUTPUTS}/run-metrics.txt"
  run_stage baseline baseline "${EPISODE_OUTPUTS}/baseline.json" "${EPISODE_OUTPUTS}/transcription-summary.json" "${EPISODE_OUTPUTS}/baseline-timing-repairs.json"
  run_stage align align "${EPISODE_OUTPUTS}/alignment.json" "${EPISODE_OUTPUTS}/summary.json" "${EPISODE_OUTPUTS}/review-input.json" "${EPISODE_OUTPUTS}/word-alignment.json"
  run_stage publish publish "${EPISODE_OUTPUTS}/publication-summary.json" "${pipeline_package}/episode.json"
fi
/bin/zsh "${pipeline_helpers}/checkpoint.zsh" verify-package
# Index is a separate edition-bound sidecar; immutable package bytes stay intact.
if [[ -f "${EPISODE_OUTPUTS}/checkpoints/index.json" ]]; then
  /bin/zsh "${pipeline_helpers}/checkpoint.zsh" verify index
else
  print -r -- 'PREP_STAGE index'
  local_index_args=(--package "$pipeline_package" --output "${EPISODE_OUTPUTS}/local-index")
  if [[ -n "$pipeline_run" ]]; then local_index_args+=(--edition "$pipeline_run"); fi
  /bin/zsh "${pipeline_scripts}/index_episode_local.zsh" "${local_index_args[@]}" > "${EPISODE_OUTPUTS}/local-index.log" 2>&1
  mkdir -p "${pipeline_package}/indexing"
  cp "${EPISODE_OUTPUTS}/local-index/index.json" "${pipeline_package}/indexing/index.json"
  cp "${EPISODE_OUTPUTS}/local-index/summary.json" "${pipeline_package}/indexing/summary.json"
  /bin/zsh "${pipeline_helpers}/checkpoint.zsh" save index "${EPISODE_OUTPUTS}/local-index/index.json" "${EPISODE_OUTPUTS}/local-index/summary.json"
  print -r -- 'PREP_STAGE_DONE index'
fi
# The app worker owns this step before its optional ChatGPT fallback.
if [[ "${EPISODE_DEFER_ENRICHMENT:-0}" != 1 ]]; then
  print -r -- 'PREP_STAGE enrich'
  enrichment_edition="${pipeline_run}"
  if [[ -z "$enrichment_edition" ]]; then enrichment_edition="$(jq -r '.edition' "${pipeline_package}/indexing/summary.json")"; fi
  enrichment_args=(--package "$pipeline_package" --edition "$enrichment_edition" --index "${pipeline_package}/indexing/index.json" --output "${EPISODE_OUTPUTS}/enrichment")
  if (( pipeline_enrichment_offline )); then enrichment_args+=(--offline); fi
  if (( pipeline_enrichment_retry )); then enrichment_args+=(--retry); fi
  /bin/zsh "${pipeline_scripts}/enrich_episode_index.zsh" "${enrichment_args[@]}" 2>&1 | tee "${EPISODE_OUTPUTS}/enrichment.log"
  print -r -- 'PREP_STAGE_DONE enrich'
fi
if (( pipeline_register )); then /bin/zsh "${pipeline_helpers}/register_package.zsh"; fi
# Remove only this run's regenerable PCM after successful durable publication.
rm -f -- "${EPISODE_WORK}/opus-ffmpeg.wav" "${EPISODE_WORK}/opus-apple.wav"
/bin/zsh "${pipeline_helpers}/checkpoint.zsh" report
print -r -- "Complete. Report: ${EPISODE_OUTPUTS}/README.md"

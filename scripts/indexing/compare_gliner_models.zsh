#!/bin/zsh
# Compare existing and upgraded GLiNER without publishing any index.
set -euo pipefail
compare_project="${0:A:h:h:h}"
compare_package="${1:-${compare_project}/work/episode-preparation/packages/d873d6f11bc0/67ab163727604fa38db69d940d6fdd88}"
compare_edition="${2:-67ab163727604fa38db69d940d6fdd88}"
compare_output="${3:-${compare_project}/outputs/gliner-upgrade-comparison}"
compare_old="${compare_project}/work/local-index-benchmark/venv/bin/python"
compare_new="${compare_project}/work/gliner-upgrade/venv/bin/python"
compare_old_cache="${compare_project}/work/local-index-benchmark/model-cache"
compare_large_cache="${compare_project}/work/gliner-upgrade/model-cache"
[[ -x "$compare_old" && -x "$compare_new" ]] || { print -u2 'Prepare the GLiNER comparison environments first; see docs/plans/GLINER_UPGRADE_COMPARISON.md.'; exit 2; }
mkdir -p "$compare_output"
# Optional fourth argument allows small-model runs while large weights download.
case "${4:-all}" in
  all) compare_arms=(0.2.24-small 0.2.30-small 0.2.30-large) ;;
  small) compare_arms=(0.2.24-small 0.2.30-small) ;;
  large) compare_arms=(0.2.30-large) ;;
  *) print -u2 'Fourth argument must be all, small or large.'; exit 2 ;;
esac
# One process per arm, serial execution avoids contention on MPS and RAM.
for compare_arm in "${compare_arms[@]}"; do
  compare_python="$compare_new"
  compare_model='urchade/gliner_small-v2.1'
  compare_revision='4e091416cf7c3481db542c2a3d26156916f3a47f'
  compare_cache="$compare_old_cache"
  if [[ "$compare_arm" == 0.2.24-small ]]; then compare_python="$compare_old"; fi
  if [[ "$compare_arm" == 0.2.30-large ]]; then
    compare_model='urchade/gliner_large-v2.1'
    compare_revision='abd49a1f1ebc12af1be84d06f6848221cf96dcad'
    compare_cache="$compare_large_cache"
  fi
  mkdir -p "${compare_output}/${compare_arm}"
  [[ ! -f "${compare_output}/${compare_arm}/summary.json" ]] || { print -u2 "Existing comparison result: ${compare_arm}. Use a new output directory."; exit 2; }
  "$compare_python" - "$compare_arm" "${compare_output}/${compare_arm}/environment.json" <<'PY'
from pathlib import Path
import importlib.metadata,json,platform,sys
arm=sys.argv[1];expected=arm.split('-')[0]
versions={p:importlib.metadata.version(p) for p in ['gliner','torch','transformers','huggingface_hub','numpy','safetensors']}
if versions['gliner']!=expected:raise SystemExit('GLiNER environment version mismatch')
Path(sys.argv[2]).write_text(json.dumps(dict(python=sys.version,executable=sys.executable,platform=platform.platform(),dependencies=versions),indent=2)+'\n')
PY
  print -r -- "Running ${compare_arm}..."
  /usr/bin/time -l env LOCAL_INDEX_PYTHON="$compare_python" LOCAL_INDEX_HF_HOME="$compare_cache" \
    /bin/zsh "${compare_project}/scripts/index_episode_local.zsh" \
    --package "$compare_package" --edition "$compare_edition" \
    --model "$compare_model" --revision "$compare_revision" \
    --output "${compare_output}/${compare_arm}" \
    > "${compare_output}/${compare_arm}/worker.log" 2> "${compare_output}/${compare_arm}/process.log"
  print -r -- "Completed ${compare_arm}."
done
print -r -- "Comparison outputs: ${compare_output}"

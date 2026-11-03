#!/bin/zsh
set -euo pipefail
trial_outputs="${0:A:h}"
trial_project="${trial_outputs:h:h}"
trial_environment="${trial_project}/work/whisperx-trial/venv"
command -v uv >/dev/null
if [[ ! -x "${trial_environment}/bin/python" ]]; then
  uv venv --python 3.13 "$trial_environment"
fi
uv pip sync --python "${trial_environment}/bin/python" "${trial_outputs}/requirements-lock.txt"
print -r -- 'Environment ready. Run run_alignment.zsh with zsh.'

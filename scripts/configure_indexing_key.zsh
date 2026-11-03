#!/bin/zsh
# Save a local trial credential without printing it or adding it to Git.
set -euo pipefail
index_key_project="${0:A:h:h}"
index_key_directory="${index_key_project}/work/indexing-trial"
umask 077
mkdir -p "$index_key_directory"
read -rs "index_api_key?OpenAI API key (hidden): "
print
[[ -n "$index_api_key" ]] || { print -u2 'No key supplied; nothing written.'; exit 2; }
print -rn -- "$index_api_key" > "${index_key_directory}/openai-api-key"
chmod 600 "${index_key_directory}/openai-api-key"
unset index_api_key
print -r -- 'Saved the trial key locally in ignored work/indexing-trial/openai-api-key.'

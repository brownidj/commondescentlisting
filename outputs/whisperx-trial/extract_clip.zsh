#!/bin/zsh
set -euo pipefail
trial_outputs="${0:A:h}"
if (( $# != 1 )); then
  print -u2 -- 'Usage: zsh extract_clip.zsh /absolute/path/to/the/captured-episode.mp3'
  exit 2
fi
[[ -s "$1" ]]
command -v ffmpeg >/dev/null
# Refuse to overwrite an existing clip: it defines the experiment's audio identity.
ffmpeg -nostdin -hide_banner -loglevel error -i "$1" \
  -t 120 -ar 16000 -ac 1 -c:a pcm_s16le -n \
  "${trial_outputs}/karoo-first-120s.wav"
shasum -a 256 "${trial_outputs}/karoo-first-120s.wav"

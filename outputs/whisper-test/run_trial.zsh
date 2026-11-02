#!/bin/zsh
set -euo pipefail
zmodload zsh/datetime

# Reproduce the selected-episode trial; this does not choose another episode.
trial_outputs="${0:A:h}"
trial_work="${WHISPER_TRIAL_WORK:-/Users/david/Documents/Codex/2026-10-31/https-chat-deepseek-com-share-nuqstl1u7xnunoiqgb/work/whisper-test}"
mkdir -p "$trial_work"

command -v whisper-cli >/dev/null
command -v ffmpeg >/dev/null
if [[ ! -s "${trial_work}/ggml-small.en.bin" ]]; then
  curl --fail --location --retry 2 \
    'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin' \
    --output "${trial_work}/ggml-small.en.bin.part"
  mv "${trial_work}/ggml-small.en.bin.part" "${trial_work}/ggml-small.en.bin"
fi
print -r -- 'c6138d6d58ecc8322097e0f987c32f1be8bb0a18532a3f88f734d1bbf9c41e5d  ggml-small.en.bin' \
  | (cd "$trial_work" && shasum -a 256 -c -)
if [[ ! -s "${trial_work}/episode.mp3" ]]; then
  curl --fail --location --retry 2 \
    'https://mcdn.podbean.com/mf/web/y8q2x6azpqqdkxrb/Episode_208_The_Karoo_Supergroup.mp3' \
    --output "${trial_work}/episode.mp3.part"
  mv "${trial_work}/episode.mp3.part" "${trial_work}/episode.mp3"
fi

ffmpeg -nostdin -hide_banner -loglevel error \
  -i "${trial_work}/episode.mp3" -ar 16000 -ac 1 -c:a pcm_s16le \
  -y "${trial_work}/episode.wav"

trial_started="$EPOCHREALTIME"
/usr/bin/time -lp -o "${trial_outputs}/timing.txt" \
  whisper-cli -m "${trial_work}/ggml-small.en.bin" \
  -f "${trial_work}/episode.wav" -l en -t 8 \
  -otxt -ovtt -osrt -oj -pp \
  -of "${trial_outputs}/episode-208-karoo" \
  > "${trial_work}/transcription.log" 2>&1
trial_finished="$EPOCHREALTIME"

print -r -- "started_epoch=${trial_started}" > "${trial_outputs}/run-metrics.txt"
print -r -- "finished_epoch=${trial_finished}" >> "${trial_outputs}/run-metrics.txt"
print -r -- "model=small.en" >> "${trial_outputs}/run-metrics.txt"
print -r -- "threads=8" >> "${trial_outputs}/run-metrics.txt"
print -r -- "Transcription completed: ${trial_outputs}/episode-208-karoo.txt"

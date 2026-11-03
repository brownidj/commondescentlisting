#!/bin/zsh
set -euo pipefail

# Run from any directory. Reproduction never writes to the episode source.
trial_outputs="${0:A:h}"
trial_project="${trial_outputs:h:h}"
trial_source="${trial_project}/flutter_app/assets/audio/episode-208-karoo.mp3"
trial_expected_sha="05920194f6cb7411cb69bfc8e1aafb348a7d84b25607104bc40f4631d134036b"
trial_expected_frames=2646000
trial_created="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

for trial_tool in ffmpeg ffprobe jq shasum; do
  command -v "$trial_tool" >/dev/null
done
[[ -x /usr/bin/afconvert && -x /usr/bin/afinfo ]]
[[ -f "$trial_source" ]]
[[ ! -e "${trial_outputs}/samples" && ! -e "${trial_outputs}/manifest.json" ]] || {
  print -u2 'A published trial already exists. Move its samples/, probes/, manifest.json and summary.tsv together before repeating.'
  exit 1
}
trial_actual_sha="$(shasum -a 256 "$trial_source")"
trial_actual_sha="${trial_actual_sha%% *}"
[[ "$trial_actual_sha" == "$trial_expected_sha" ]] || {
  print -u2 'The source audio edition has changed; this trial requires the recorded Karoo edition.'
  exit 1
}

mkdir -p "${trial_project}/work/audio-compression-trial"
trial_work="$(mktemp -d "${trial_project}/work/audio-compression-trial/run.XXXXXXXX")"
mkdir -p "${trial_work}/samples" "${trial_work}/probes"
trial_records="${trial_work}/records.jsonl"
: > "$trial_records"
ffmpeg -version > "${trial_work}/probes/ffmpeg-version.txt"
sw_vers > "${trial_work}/probes/macos-version.txt"
ffprobe -v error -show_format -show_streams -of json "$trial_source" > "${trial_work}/probes/source.json"
trial_duration="$(jq -r '.format.duration' "${trial_work}/probes/source.json")"
trial_source_bytes="$(jq -r '.format.size' "${trial_work}/probes/source.json")"

typeset -a trial_ids trial_starts
trial_ids=(opening science closing)
trial_starts=(0 3290 6480)

for ((trial_index = 1; trial_index <= ${#trial_ids}; trial_index++)); do
  trial_id="${trial_ids[$trial_index]}"
  trial_start="${trial_starts[$trial_index]}"
  trial_pcm="${trial_work}/${trial_id}.wav"
  print "Extracting ${trial_id} at ${trial_start}s"
  ffmpeg -hide_banner -nostdin -loglevel error -n -i "$trial_source" \
    -ss "$trial_start" -t 60 -map 0:a:0 -map_metadata -1 \
    -ac 1 -ar 44100 -c:a pcm_s16le "$trial_pcm"
  ffprobe -v error -show_streams -of json "$trial_pcm" > "${trial_work}/probes/${trial_id}-pcm.json"
  jq -e --argjson frames "$trial_expected_frames" \
    '.streams[0] | .channels == 1 and .sample_rate == "44100" and .duration_ts == $frames' \
    "${trial_work}/probes/${trial_id}-pcm.json" >/dev/null

  for trial_variant in reference he-aac-24 he-aac-32 opus-16 opus-24; do
    trial_target_kbps=0
    case "$trial_variant" in
      reference)
        trial_file="${trial_id}-${trial_variant}.flac"
        ffmpeg -hide_banner -nostdin -loglevel error -n -i "$trial_pcm" \
          -map_metadata -1 -c:a flac -compression_level 8 "${trial_work}/samples/${trial_file}"
        ;;
      he-aac-*)
        trial_target_kbps="${trial_variant##*-}"
        trial_file="${trial_id}-${trial_variant}.m4a"
        /usr/bin/afconvert -f m4af -d aach -c 1 \
          -b "$((trial_target_kbps * 1000))" -q 127 -s 0 --no-filler \
          "$trial_pcm" "${trial_work}/samples/${trial_file}"
        ;;
      opus-*)
        trial_target_kbps="${trial_variant##*-}"
        trial_file="${trial_id}-${trial_variant}.opus"
        ffmpeg -hide_banner -nostdin -loglevel error -n -i "$trial_pcm" \
          -map_metadata -1 -ac 1 -ar 48000 -c:a libopus \
          -b:a "${trial_target_kbps}k" -application audio -vbr constrained \
          -compression_level 10 "${trial_work}/samples/${trial_file}"
        ;;
    esac
    trial_encoded="${trial_work}/samples/${trial_file}"
    trial_probe="${trial_work}/probes/${trial_id}-${trial_variant}"
    ffprobe -v error -show_format -show_streams -of json "$trial_encoded" > "${trial_probe}.json"
    ffmpeg -hide_banner -nostdin -loglevel error -n -i "$trial_encoded" \
      -map 0:a:0 -ac 1 -ar 44100 -c:a pcm_s16le \
      "${trial_work}/${trial_id}-${trial_variant}-ffmpeg.wav"
    ffprobe -v error -show_streams -of json \
      "${trial_work}/${trial_id}-${trial_variant}-ffmpeg.wav" > "${trial_probe}-ffmpeg-decode.json"

    # Native decoding separately checks packet priming/remainder handling.
    trial_apple_options=()
    if [[ "$trial_variant" == he-aac-* ]]; then
      trial_apple_options=(--decode-formatid aach)
    fi
    trial_apple_ok=false
    trial_apple_frames=null
    if /usr/bin/afconvert -f WAVE -d LEI16@44100 "${trial_apple_options[@]}" \
      "$trial_encoded" "${trial_work}/${trial_id}-${trial_variant}-apple.wav" \
      > "${trial_probe}-apple-decode.log" 2>&1; then
      trial_apple_ok=true
      ffprobe -v error -show_streams -of json \
        "${trial_work}/${trial_id}-${trial_variant}-apple.wav" > "${trial_probe}-apple-decode.json"
      trial_apple_frames="$(jq -r '.streams[0].duration_ts' "${trial_probe}-apple-decode.json")"
    fi
    /usr/bin/afinfo "$trial_encoded" > "${trial_probe}-afinfo.txt" 2>&1 || true
    if [[ "$trial_variant" == he-aac-* ]]; then
      # HE-AAC's native format list is authoritative for this mono trial.
      [[ "$trial_apple_ok" == true && "$trial_apple_frames" == "$trial_expected_frames" ]]
      rg -q 'Channel layout: Mono' "${trial_probe}-afinfo.txt"
      rg -q 'aach' "${trial_probe}-afinfo.txt"
    fi
    trial_sha="$(shasum -a 256 "$trial_encoded")"
    trial_sha="${trial_sha%% *}"
    jq -n --arg sample "$trial_id" --arg variant "$trial_variant" \
      --arg file "samples/${trial_file}" --arg sha256 "$trial_sha" \
      --argjson source_start_s "$trial_start" --argjson target_kbps "$trial_target_kbps" \
      --argjson native_decode_ok "$trial_apple_ok" --argjson native_frames "$trial_apple_frames" \
      --argjson episode_duration "$trial_duration" --argjson original_bytes "$trial_source_bytes" \
      --slurpfile probe "${trial_probe}.json" \
      --slurpfile decoded "${trial_probe}-ffmpeg-decode.json" \
      '{sample:$sample, variant:$variant, file:$file, sha256:$sha256,
        source_start_s:$source_start_s, excerpt_duration_s:60, target_kbps:$target_kbps,
        bytes:($probe[0].format.size|tonumber),
        container_duration_s:($probe[0].format.duration|tonumber),
        ffmpeg_profile:($probe[0].streams[0].profile // null),
        ffmpeg_reported_channels:$probe[0].streams[0].channels,
        ffmpeg_decoded_frames_44100:$decoded[0].streams[0].duration_ts,
        native_decode_ok:$native_decode_ok, native_decoded_frames_44100:$native_frames,
        projected_episode_mib:((($probe[0].format.size|tonumber)/60*$episode_duration)/1048576),
        projected_reduction_percent:(100*(1-(($probe[0].format.size|tonumber)/60*$episode_duration)/$original_bytes))}' \
      >> "$trial_records"
    print "Created ${trial_file}"
  done
done

jq -s --arg created_at_utc "$trial_created" --arg source_sha256 "$trial_expected_sha" \
  --argjson source_duration_s "$trial_duration" --argjson source_bytes "$trial_source_bytes" \
  '{schema_version:1, created_at_utc:$created_at_utc,
    source:{episode:208,title:"The Karoo Supergroup",sha256:$source_sha256,
      project_path:"flutter_app/assets/audio/episode-208-karoo.mp3",
      duration_s:$source_duration_s,bytes:$source_bytes,channels:1},
    reference:"Lossless FLAC of the common decoded MP3 excerpt; not a studio master.",
    method:"Identical 60-second mono PCM inputs; no gain, denoising, trimming within excerpts, or speed changes. Apple HE-AAC CBR; constrained-VBR libopus audio mode.",
    limitations:["Size projections use excerpts, not full-episode encodes.",
      "Decode duration is not a measurement of acoustic alignment or native seeking.",
      "Listening, Flutter player, and iOS acceptance remain pending.",
      "FFmpeg interprets Apple implicit-SBR HE-AAC differently from native decoding; see probes."],
    samples:.}' "$trial_records" > "${trial_work}/manifest.json"
jq -r '(["sample","variant","bytes","container_duration_s","ffmpeg_decoded_frames_44100","native_decode_ok","native_decoded_frames_44100","projected_episode_mib"]|@tsv),
  (.samples[]|[.sample,.variant,.bytes,.container_duration_s,.ffmpeg_decoded_frames_44100,.native_decode_ok,.native_decoded_frames_44100,.projected_episode_mib]|@tsv)' \
  "${trial_work}/manifest.json" > "${trial_work}/summary.tsv"
jq -r '"const trialManifest = " + (.|tojson) + ";"' \
  "${trial_work}/manifest.json" > "${trial_work}/comparison-data.js"

# Publish only after encoding, decoding and the native HE-AAC frame checks succeed.
mv "${trial_work}/samples" "${trial_outputs}/samples"
mv "${trial_work}/probes" "${trial_outputs}/probes"
mv "${trial_work}/manifest.json" "${trial_work}/summary.tsv" \
  "${trial_work}/comparison-data.js" "$trial_outputs/"
print "Published comparison samples to ${trial_outputs}"
print "Temporary PCM remains in ${trial_work}"

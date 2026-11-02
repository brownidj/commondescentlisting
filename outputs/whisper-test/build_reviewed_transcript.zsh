#!/bin/zsh
# Regenerate the reviewed listener files from the untouched Whisper baseline.
set -euo pipefail
readonly transcript_dir="${0:A:h}"
readonly project_dir="${transcript_dir:h:h}"
cd "$transcript_dir"
readonly expected_hash='50726f4e7f8fbe0b411f826081a2f4ee309860d5ab26cc6b8a28cfe09c837223'
readonly actual_hash="$(shasum -a 256 episode-208-karoo.txt | cut -d ' ' -f 1)"
if [[ "$actual_hash" != "$expected_hash" ]]; then
  print -u2 'Original transcript has changed; review correction coordinates before continuing.'
  exit 1
fi
readonly staging="$(mktemp -d "$transcript_dir/.reviewed.XXXXXX")"
trap 'rm -rf "$staging"' EXIT

jq --rawfile rules corrections.tsv \
   --rawfile review episode-208-karoo-review.md \
   --rawfile original episode-208-karoo.txt \
   --slurpfile episode episode.json --arg hash "$expected_hash" '
  ($review | split("\n") | map(select(startswith("| ")))
    | map(split("|") | map(gsub("^ +| +$"; "")))
    # Normalise the review table with Passage + TXT columns to the original
    # layout used below. Keep compatibility with earlier single-column reviews.
    | map(if length == 8 then del(.[1]) else . end)
    | map(select(.[4] | startswith("High") or startswith("Medium")))) as $rows |
  ($rules | split("\n") | map(select(length > 0) | split("\t"))
    | map({group: (.[0] | tonumber), lines: .[1], before: .[2], after: .[3]})) as $rules |
  if (.transcription | length) != 1032 or
     ([.transcription[].text | ltrimstr(" ")] | join("\n") + "\n") != $original
    then error("Baseline TXT and JSON cue mapping differ") else . end |
  .transcription | to_entries | map(
    . as $entry | ($entry.key + 1) as $line |
    reduce $rules[] as $rule
      ({line: $line, start_ms: $entry.value.offsets.from,
        end_ms: $entry.value.offsets.to, text: $entry.value.text,
        original_text: $entry.value.text, changes: []};
       if ($rule.lines == "*" or
           ($rule.lines | split(",") | index($line | tostring)) != null)
          and (.text | contains($rule.before)) then
         ($rows[$rule.group - 1]) as $row |
         if ($row[4] | startswith("High") | not) then
           error("Rule is not approved High confidence") else
           .text = (.text | split($rule.before) | join($rule.after)) |
           .changes += [{review_group: $rule.group, before: $rule.before,
             after: $rule.after, confidence: $row[4], reason: $row[5]}]
         end
       else . end)
  ) as $cues |
  {schema_version: 1, episode_guid: $episode[0].guid,
    title: $episode[0].title,
    review: {label: "Machine transcribed; names and terminology reviewed.",
      date: "2026-10-31", audio_checked: false,
      note: "High-confidence contextual corrections only. Uncertain passages retain the original wording. Timing is machine generated and has not been checked against the audio.",
      original_txt_sha256: $hash, source: "episode-208-karoo.json",
      correction_review: "episode-208-karoo-review.md"},
    segments: ($cues | map({id: .line, start_ms, end_ms, text: (.text | ltrimstr(" "))})),
    changes: ($cues | map(select(.changes | length > 0))),
    unresolved: [
      {lines: [545], reason: "Wording of the Karoo joke cannot be recovered from context."},
      {lines: [685], reason: "Dicynodon versus dicynodont: medium-confidence proposal; retained pending audio check."},
      {lines: [727], reason: "castroides: genus uncertain; do not infer Castoroides or Palaeocastor from the burrow comparison."},
      {lines: [928], reason: "drassic: could be Jurassic or Triassic; retained pending audio check."},
      {lines: [694,736], reason: "Walking with Dinosaurs reference: retain the speakers wording, including any factual slip."},
      {lines: [972], reason: "alleys episodes: Aly’s is a medium-confidence identification; retained pending confirmation."},
      {lines: [22,43,898,926,999], reason: "Audience/patron names have not been authenticated; retain spelling pending confirmation."}
    ]}
' episode-208-karoo.json > "$staging/episode-208-karoo-reviewed.json"

# All exports and the listener asset come from this single reviewed document.
jq -r '.segments[].text' "$staging/episode-208-karoo-reviewed.json" > "$staging/episode-208-karoo-reviewed.txt"
for caption_format in vtt srt; do
  jq -r --arg format "$caption_format" '
    def pad($n): tostring | ("000" + .)[-$n:];
    def stamp($ms):
      (($ms / 3600000 | floor | pad(2)) + ":" +
       (($ms / 60000 | floor) % 60 | pad(2)) + ":" +
       (($ms / 1000 | floor) % 60 | pad(2)) +
       (if $format == "vtt" then "." else "," end) +
       ($ms % 1000 | pad(3)));
    (if $format == "vtt" then "WEBVTT\n" else empty end),
    (.segments[] |
      (if $format == "srt" then (.id | tostring) + "\n" else "" end) +
      stamp(.start_ms) + " --> " + stamp(.end_ms) + "\n" + .text + "\n")
  ' "$staging/episode-208-karoo-reviewed.json" > "$staging/episode-208-karoo-reviewed.$caption_format"
done
jq -r '
  "# Episode 208: applied transcript corrections\n",
  .review.label, .review.note,
  "\nOriginal TXT SHA-256: `" + .review.original_txt_sha256 + "`\n",
  "High-confidence groups applied: " + ([.changes[].changes[].review_group] | unique | length | tostring),
  "Changed cues: " + (.changes | length | tostring),
  "\nEach entry records the complete before/after cue. Times and cue IDs match the original. See the JSON for individual replacement rules and the linked evidence from the contextual review.\n",
  (.changes[] |
    "## Cue " + (.line | tostring) + " — " + (.start_ms / 1000 | tostring) + " s\n\n" +
    "Original: " + .original_text + "\n\nReviewed: " + .text + "\n\n" +
    ([.changes[] | "- " + .confidence + ": " + .reason] | unique | join("\n")) + "\n"),
  "## Unresolved: no substitutions\n",
  (.unresolved[] | "- Cue(s) " + (.lines | map(tostring) | join(", ")) + ": " + .reason)
' "$staging/episode-208-karoo-reviewed.json" > "$staging/episode-208-karoo-changes.md"

mv "$staging"/episode-208-karoo-* "$transcript_dir/"
mkdir -p "$project_dir/docs/transcripts" "$project_dir/flutter_app/assets/transcripts"
cp episode-208-karoo-reviewed.txt "$project_dir/docs/transcripts/"
cp episode-208-karoo-reviewed.json "$project_dir/flutter_app/assets/transcripts/"
print 'Reviewed JSON, TXT, VTT, SRT, change log and listener asset generated.'

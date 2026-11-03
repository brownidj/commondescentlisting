# Episode 72 — Plesiosaurs transcript

Authorised 2 November 2026: make a transcript of Episode 72, using the established
local transcription/compressed-audio workflow.

Goal: deliver the complete transcript in docs/transcripts and an episode package
usable by the existing transcript reader. Scope is Episode 72 only; Karoo and
installed listener journals remain unchanged. No contextual rewriting or claim of
human review. Scientific names and ambiguous words must remain visibly unreviewed.

Tasks: obtain episode identity/enclosure from the saved catalogue; capture the
audio once into ignored work storage and fingerprint it; transcribe that source
with the existing whisper.cpp small.en model; encode a mono 16 kbps-target Opus
recording; align the detected passage text against the final Opus decode with
WhisperX; publish a stable-key folder, baseline/alignment/word files, listener
TXT/JSON/VTT/SRT, segment snapshot and provenance. Register the prepared package
alongside Karoo. All processing entry points use zsh, invoking WhisperX's Python
API where necessary. No source-download file is placed inside the package.

Acceptance: successful complete transcription; stable IDs and original text/time
references; retained raw Whisper output; final audio hash paired with alignment;
ordered/bounded positive passage timings, with low-confidence/untimed cases
explicitly flagged rather than hidden. Publication checks artifact hashes and
ensures the existing Karoo package is unchanged. Transcript copies are saved in
docs/transcripts. Source is retained in ignored work until acceptance.

Done when generation/processing actually run, outputs and app registration are
supplied, and limitations are recorded. Media download/transcription/alignment
and processing integrity checks are authorised. Flutter tests, analysis, builds
and product launches retain the manual default. No Git mutations, source disposal,
other-episode processing or general redownload feature in this increment.

Completed: source captured (51,124,069 bytes), transcribed in 144.646 seconds to
990 passages / approximately 15,821 words. Opus: 13,248,456 bytes, 74.09% smaller,
SHA-256 a8bc989316f5c4193f20862a814a5e08f0e239631052955f4bba6d819c7c729c.
WhisperX measured all 990 passages against the final Opus in 286.519 seconds;
two joint boundary realignments, no missing timings or automatic acoustic flags.
Text remains explicitly machine-generated and unreviewed, including recognised
scientific-name errors. Native macOS media inspection completed seven paused
seeks; Apple/FFmpeg returned matching sample counts. No audible/iOS acceptance.

Published 16.0 MiB package under assets/episodes/d111dc1276ec736e782a70ac43fed94c/
and copied TXT/JSON/VTT/SRT to docs/transcripts/episode-072-plesiosaurs.*. Registered
alongside Karoo and added a focused second-episode repository regression. Karoo
manifest/payload hashes were checked unchanged; no existing journal rewritten.
Source retained in ignored work; regenerable PCM cleaned up. All launchers use
zsh. Two affected Dart files formatted; Flutter tests/analysis/builds/product
launches not run. See outputs/episodes/d111dc1276ec736e782a70ac43fed94c/legacy/README.md for evidence and
manual verification. Unphased work; generation complete, acceptance pending.

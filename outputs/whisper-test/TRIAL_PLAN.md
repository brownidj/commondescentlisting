# Local whisper.cpp trial

Goal: transcribe one randomly selected Common Descent episode locally, save
timestamped outputs, and measure processing time without a paid API.

Selection: uniform random choice from the 391 saved RSS entries, index 77:
Episode 208 — The Karoo Supergroup. Selection metadata is in episode.json.

Environment: Apple M4 Pro, 24 GiB RAM, arm64 macOS. Homebrew whisper.cpp 1.9.5,
English small.en model, default decoding and Metal acceleration where available.
No custom vocabulary prompt or reference transcript is supplied.

Scope: download this episode and the model; convert to 16 kHz mono PCM; transcribe
the full audio; produce TXT, SRT, VTT and JSON; inspect output coverage and a few
scientific terms; record elapsed time and caveats. Do not transcribe the catalogue
or integrate transcripts into Flutter in this trial.

Acceptance: successful CLI exit, non-empty text/captions/JSON, sensible increasing
timestamps covering the source duration, reproducible zsh invocation, measured
runtime. Text inspection is a spot check, not an accuracy benchmark. Native
audio listening/manual comparison is recorded separately if performed.

The user explicitly authorised running this trial. No Flutter checks, changes
to the application, or Git mutations are required or authorised by it.

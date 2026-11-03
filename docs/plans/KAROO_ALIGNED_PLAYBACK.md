# Complete Karoo aligned playback

Authorised 2 November 2026. Goal: deliver full-episode word alignment and make the
app play the exact fixed audio edition used for it on macOS/iOS.

Scope: Episode 208 only; bundle the previously captured MP3 and a separate aligned
timing asset. Keep original transcript IDs, wording, timestamps and nine local
text revisions recoverable. Preserve original timing identity for edit journals.
Calibration belongs to an audio edition: old advertised-stream offsets must not
be added to the fixed audio. Nudge continues saving for the active edition.

Tasks: run full WhisperX alignment with neighbouring text context; reconcile
chunk boundaries using joint alignment, flag low-confidence results; validate
complete, bounded, ordered timing coverage; register fixed asset playback in the
native engine/controller; load aligned cues while retaining original provenance;
scope calibration to audio identity; update exports/diagnostics and focused tests.

Acceptance: all 1032 original IDs retained, listener text preserved, audio hash
fixed and matched by alignment metadata, same source used for play/replay/resume,
valid non-overlapping positive cue spans, legacy journal loads without discarded
edits, old stream offset ignored for fixed audio, new Nudge persists/reloads,
other episodes retain current streaming behavior. Any unresolved acoustic timing
uncertainty remains visible rather than reported as human-verified accuracy.

Done when full alignment is executed, assets/app integration and regression
coverage are supplied, and verification evidence/limitations are recorded.
Alignment execution is authorised. Flutter tests/analysis/native builds and
launches retain the manual default unless David explicitly authorises those.

Implementation completed: 1032 passages aligned in 312.227 seconds. Four boundary
pairs jointly re-aligned; no residual overlaps or missing passage timings. Passage
1025 alone has a low-score listening-review flag. Original baseline and installed
journal unchanged. Fixed audio and alignment assets registered; legacy revision
timing references and per-audio calibration preserved. Export formats and timing
diagnostics identify the fixed edition. Focused regression tests supplied; Flutter
analysis/tests, native builds/launches and listening verification remain pending.
See outputs/karoo-aligned/RESULTS.md for evidence and exact commands.

Reported skip issue: request precise duration/timing for fixed assets through
just_audio's DarwinAssetOptions rather than relying on its default false. Track
successful explicit seeks independently of natural progress/calibration; clear
a held edit selection on explicit seeking so audio-follow resumes (except editor
auditions/diagnostics). Acceptance: forward/back skips retain audio source and
saved Nudge, highlight/follow the newly calculated passage, failed seeks do not
clear selection, and normal playback keeps manual selection stationary. Add focused
source configuration, state and widget coverage. Native seek precision remains to
be verified on macOS/iOS; no calibration or aligned timing asset changes.

# Reusable episode preparation pipeline

Goal: one zsh entry point taking an episode number, replacing per-episode script
copies with shared stages. Scope: local capture, final 16 kbps mono Opus,
whisper.cpp transcription of that Opus decode, WhisperX alignment, validated
package/export publication, optional app registration and explicit source cleanup.
No new episode processing, dependency installation, Flutter runs or Git mutations
are requested in this implementation task.

Tasks: parameterize the proven Episode 54 helpers; add configuration/preflight,
exclusive processing locks, hash-based stage checkpoints and safe resume; preserve
existing editions and journals; write completion/uncertainty reports; document
commands and meaningful failure/recovery acceptance scenarios.

Acceptance: no episode-specific paths, titles or GUIDs in shared helpers; outputs
inside project outputs and PCM/downloads inside ignored work; all runnable scripts
use zsh. Transcription and alignment use the same compressed waveform. Config or
checkpoint mismatch must stop. Publication must verify bounded positive timings,
identities and artifact hashes. Existing packages cannot be overwritten. Original
deletion is a separate explicit operation, after successful publication. Optional
registration must be idempotent, backed up, and leave other resources intact.

Done when scripts and usage/completion documentation are saved, static inspection
is complete, and unrun end-to-end/Flutter acceptance is explicitly recorded.
Verification remains manual per project criteria. No tests, analysis, builds,
product launches or live media processing by the assistant for this task.

Implemented 3 November 2026: generic entry point and six shared zsh helpers,
checkpoint/resume and post-rename publication recovery, optional idempotent app
registration with backups, explicit original disposal, generated reports and
usage documentation. No existing app resources/journals were modified. Added an
offline fixture regression, not run. Syntax-only parsing passed for eight zsh
scripts and eleven embedded Python blocks. No pipeline/media/Flutter/test/Git
execution. Behavioural acceptance pending. See scripts/README.md and
outputs/episode-pipeline/IMPLEMENTATION.md for commands, limits and checklist.

Default update authorised 3 November 2026: use medium.en for new runs and enable
Flutter package registration by default. Keep --model/WHISPER_MODEL overrides,
explicit --register compatibility and add --no-register. Preserve the saved model
for resumed runs and the configuration mismatch guard. Cache the publisher's
medium.en model locally after verifying its SHA-256. No episode reprocessing,
Flutter/test launch or existing package/journal replacement in this change.

Word mapping fix, 3 November 2026: preserve the entire acoustic window during WhisperX sentence postprocessing to avoid splitting possessive citations such as et al.'s. Retain exact word-map guards and save raw failure diagnostics. Added offline regression. David authorised offline and failed-window verification: 2 tests passed and all 96 words mapped exactly for Episode 72 passages 1196–1205. No full rerun or activation. Existing publication/identity guards remain. See outputs/alignment-word-mapping-check/RESULTS.md.

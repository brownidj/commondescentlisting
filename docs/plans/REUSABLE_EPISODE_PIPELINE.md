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

## Recoverable recognition timing and preparation resume — 4 November 2026

Goal/scope: keep literal words and passage IDs when Whisper emits zero-duration
or slightly overlapping cues. Before alignment, assign positive, ordered provisional
intervals with at most 1 second displacement per endpoint. Reject missing words,
malformed/reversed timings, large overlap, or impossible bounds with precise errors.
Keep raw recognition immutable. Record every repair in baseline-timing-repairs.json,
baseline.json and transcription-summary.json; alignment still establishes acoustic
timing and final publication retains strict validation.

Resume preparation is an explicit failed/cancelled job action. Reuse its run ID,
model, audio identity and ChatGPT setting. Verify checkpoint hashes and saved input
configuration; skip completed stages. Append logs and archive previous job status.
A narrow migration accepts the known pre-recovery script fingerprints only before
baseline completion, verifies all completed artifacts before changing configuration,
and records the original configuration and replacement code hashes. Other changed
inputs/code still fail. Resume does not automatically retry enrichment or an API
request that may already have been billed. These retain their separate retry flows.
After worker restart, the current-job endpoint exposes the latest resumable failure.

Acceptance: a zero-duration cue preserves words/IDs, valid cues stay unchanged,
small repairs are recorded, serious defects fail with actionable details, no-request
failures show ChatGPT as not reached, and resume leaves checked downloads/transcripts
unchanged. Prior editions stay active until final validation/activation succeeds.

Implemented, verification pending. Added scripts/tests/baseline_recovery_test.zsh;
no tests, analysis, builds, application/worker launches, live processing or Git actions
were run. David should run the focused offline test, preparation flow tests and
Flutter analysis, then restart worker/app and choose Resume preparation for Burgess
Shale. Check log checkpoint skips, repair audit, final audio/text alignment and that
activation occurs only after completion. Unphased task; suggested commit message:
`Handle recoverable transcript timings and resume preparation checkpoints`.

## Checkpointed acoustic alignment and group recovery — 5 November 2026

Goal: retain expensive acoustic calls across cancellation/failure, diagnose exact
conflicting passages, and resolve connected groups consistently without weakening
final publication validation. Scope: shared aligner, bounded recovery/cache helper,
known pre-alignment resume migration, offline regressions and manual handover.
No live reprocessing, tests, builds, app/worker launches or paid API requests are
part of this implementation task.

Tasks/acceptance:
- Persist each successful model call atomically, with checksummed result and exact
  request. Namespace by final audio SHA, baseline SHA, journal SHA, alignment model
  weight SHA, dependency versions and inference settings. Changed inputs use a
  separate namespace; corrupt matching checkpoints fail instead of being adopted.
- Reuse completed calls on resume; interruption must retain all earlier calls.
  Word mapping remains exact. Record lightweight chunk progress immediately.
- Diagnose invalid/out-of-bounds/overlapping passages before each repair pass,
  retaining text, original cue bounds, raw word times and scores. Realign merged
  connected windows with 2/4/8 passages of context, adopting every passage in
  each window. Limit recovery windows to 80 passages and 180 seconds.
- Three bounded passes only. Cache repair calls as well as initial calls.
- Persist complete alignment candidates and raw calls before display validation.
  Permit shared display boundaries only for ordered overlaps <=500 ms, within
  feasible positive bounds. Contained/reversed/large or non-positive spans remain
  failures, never silently replaced with invented accurate-looking timings.
- Failure writes alignment-failure.json plus a readable alignment-failure.md with
  IDs, text, baseline/candidate intervals and mean scores. Final validation marker
  distinguishes pending/failed/passed; old failure details stay retained if a later
  attempt passes. Raw acoustic words are not modified by display reconciliation.
- Preserve the strict final ordered, positive, bounded, same-ID/text/audio/journal
  checks and prior active edition. Archive earlier alignment logs on retry.
- Permit a narrow audited migration from the known predecessor aligner/entrypoint
  for unfinished pre-alignment runs, including Supercontinents, only with unchanged
  other inputs/helpers and verified completed artifacts. Completed alignment or
  publication checkpoints forbid migration. Do not mutate existing runs now.

Implemented, not runtime-verified. Created alignment_recovery.py and
scripts/tests/alignment_recovery_test.zsh; modified align_transcript.zsh and
prepare_episode.zsh. Added offline cases for cache reuse/input changes/corruption/
interruption, whole-window adoption, bounded unresolved failure, small vs unsafe
boundaries and positive/negative migration scenarios. No tests/analysis/builds or
live alignment executed. No files removed and no Git operations.

David should run `zsh scripts/tests/alignment_recovery_test.zsh`, then Resume
preparation for Supercontinents. One full alignment is still required because its
old failed attempts saved no acoustic chunks. Further retries can reuse calls;
persistently ambiguous passages may still need listening review. No worker/app
restart is required solely for these zsh/helper changes. Verify cache hits after
an interruption, exact conflict diagnostics if any, final activation only after
validation, and start/middle/end listening alignment. Record tester/date/system/
results. Phase not applicable. Suggested commit:
`Checkpoint acoustic alignment and recover connected timing conflicts`.

### Acoustic numeric boundary correction — 6 November 2026

Diagnosis: the new exact-type check rejected finite numpy.float64 / numpy.float32
values emitted by WhisperX's pandas-based word aggregation. This is a wrapper
integration defect, not evidence that the acoustic timestamp itself is malformed.
The exception was raised before the call was saved, and the validation marker
incorrectly stayed in_progress. Read-only inspection of installed WhisperX and a
pandas scalar confirmed the type mismatch; no model inference was needed.

Fix: normalize real numeric scalars (excluding booleans as timestamps) to native
JSON numbers at the library boundary. Reject non-finite, nonnumeric or reversed
word timings with the exact field/word/value, preserving strict final guards.
Persist a JSON-safe raw call before normalization or validation, including explicit
representations for non-finite/unsupported values. Failed validation records its
passage IDs, request, raw evidence path and a failed validation marker. Only valid
normalized calls become reusable checkpoints. No interpolation or fabricated
acoustic times is introduced.

Known failed predecessor can migrate after the usual unchanged-input/artifact
checks; no live run/configuration is changed during implementation. Expanded the
focused regression suite to use real NumPy values from the existing WhisperX
venv, normalization/cache reuse, invalid-value evidence and migration. Explicit
permission to run the focused offline tests has been requested; do not assume
permission from elapsed time. No live alignment/app/build/worker or paid request
was started. Original overlap recovery still needs runtime/listening acceptance.
Suggested commit: `Normalize WhisperX numeric scalars and preserve failed call evidence`.

Offline verification authorised and completed — 6 November 2026:
`zsh scripts/tests/alignment_recovery_test.zsh` passed all 15 tests (0.028 seconds).
Includes real NumPy scalar normalization, rejected invalid timing with saved raw
evidence, cache reuse/corruption/interruption, group adoption, boundary guards and
migration scenarios. No audio/model processing, paid API request, app/worker launch,
Flutter check or live alignment performed. Full acoustic/listening acceptance
still pending; fixture success does not establish Supercontinents alignment.

### Select a consistent path from cached acoustic alternatives — 7 November 2026

Measured failure: final passage 1050 was assigned the earlier “what if” occurrence
inside passage 1049, producing a 1,811 ms overlap. The cache also contains a 1044–1053
call placing passage 1050 at 7,508,931–7,512,913 ms, after 1049 ends at 7,508,291 ms.
Expanding/adopting complete repair windows can move a conflict to a window edge;
more inference does not by itself prevent this repeated-phrase error.

Goal/scope: select complete chronologically consistent passage timings from all
verified calls in the same cache namespace before any extra inference, then again
after bounded group recovery if necessary. Dynamic programming prefers the fewest
changed passages, then higher aggregate mean word scores. It never creates word
times, edits transcript wording or silently bypasses the existing display/final
validator. Candidate evidence must match namespace, request filename fingerprint,
result checksum, exact passage text and exact word mapping. No full path means no
partial adoption. Save selected calls, old/new bounds and policy in
alignment-alternative-selection.json; selected passages carry provenance flags.
A narrow known-predecessor migration retains prior input/artifact protections.

Verification authorised under the ongoing focused offline-test scope: 19 tests
passed (0.036 s). One initial fixture failure used exactly the permitted 500 ms
boundary overlap, so it legitimately kept current timing; corrected the fixture
to exceed that threshold, then all tests passed. Added repeated-phrase, no-path,
no-unnecessary-change and predecessor migration fixtures.

Read-only cached-data diagnosis (no model inference): complete valid path for all
1,156 passages from the failed final candidate, changing only passage 1050, no
shared boundaries or remaining problems. Replaying production's 393 original
chunk owners and then selecting from the same cache also passes all 1,156
passages, changing original selections 168 and 1156 and reconciling two permitted
small display overlaps. Neither replay activates an episode or mutates its run.
Evidence is in outputs/alignment-recovery/supercontinents-cached-path/.

Created no production files; modified alignment_recovery.py, align_transcript.zsh,
prepare_episode.zsh and the focused zsh test. No audio processing, new paid request,
worker/app restart, Flutter test/analysis/build, Git mutation or live preparation
resume. Existing saved cache/run artifacts remain unchanged. Implementation and
offline verification complete; end-to-end activation/listening still pending.
Use Resume preparation; matching caches should avoid acoustic inference. Review
final flags and passage 1049–1050 playback. Phase not applicable. Suggested commit:
`Select consistent cached alignment paths before repeating inference`.

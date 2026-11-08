# Prepare the selected episode from the app

Goal: offer preparation on the selected episode, choose a transcription model,
confirm re-preparation, select redownload versus larger-model retranscription,
show honest time estimates and measured progress, and activate a validated local
edition without rebuilding the app.

Scope: macOS preparation using the existing zsh/Whisper/Opus pipeline. Keep the
sandbox; a local worker is the proposed bridge, with one-time setup documented.
The existing iOS player/reader remains usable; local macOS tools cannot run on iOS.
No automatic live transcription, dependency installation, Flutter execution or Git
mutation during implementation. Model downloads occur on selection by the user.

Tasks: shared model catalogue with pinned SHA-256/size/rank; isolated per-job
work/output and immutable candidate packages; source reuse or explicit redownload;
JSON stage progress from ffmpeg/whisper.cpp/WhisperX; worker status/jobs/models and
persistent atomic local index; Dart service and dialogs; audio/transcript library
facades, startup reconnect, error handling and targeted regressions.

Acceptance: prepared state comes from disk/manifest, not just whether a process
ran. Confirm Yes before re-preparation, offer only larger models for upgrade,
show expected time before every run (ranges labelled estimates) and live elapsed,
stage and progress. Missing models can download with verified hashes and download
progress. No shell interpolation of episode/title/model. Single active job;
retain prior edition on failure, preserve journals and prevent stale timing reuse.
Cancellation must terminate descendants and release only owned locks. Worker
bound to loopback with random authentication, reject browser origins, constrained
paths and payloads; no arbitrary command endpoint. Runtime files stay in project.

Done when code, zsh launchers, docs and focused tests are supplied. Syntax checking
and formatting allowed; tests/analysis/builds/media jobs remain manual. Distinguish
implementation from unrun end-to-end/macOS device acceptance. User confirmed option 1 (local worker) during implementation. Keep the macOS
sandbox and use one-time worker startup; all episode jobs are then controlled
from the app.

Implemented: local worker (confirmed option 1), authenticated connection, model
catalogue/downloads, isolated candidate runs, retained-audio reuse or redownload,
confirmation/model dialogs, estimates/progress/background/cancel, atomic local
library and runtime audio/transcript loading, edition-specific journals and
changed-audio bookmark protection. CLI defaults preserved. No entitlements removed.

Evidence: 18 affected Dart files formatted; ten zsh scripts and thirteen embedded
Python blocks syntax-parsed; JSON/plist parsed. Eleven focused tests supplied,
none executed. No live worker/job, downloads, Flutter checks or Git mutations.
Implementation complete; end-to-end acceptance pending. See
outputs/in-app-episode-preparation/README.md and docs/IN_APP_EPISODE_PREPARATION.md.

POST framing fix (3 November 2026): worker correctly requires a bounded JSON
Content-Length, but Dart HttpClient defaulted to chunked writes. Encode UTF-8 once,
set its byte length and send those exact bytes. Add a transport regression using
a real loopback HTTP receiver, including Unicode payload and empty cancellation
object. No worker protocol relaxation or size-limit change. Verification manual.

Analyzer cleanup (3 November 2026): initialize the optional settings-file loader
with an initializing formal while retaining its public named argument; emit
lowerCamelCase generated registration names and migrate the old underscore name
when rerunning registration. Rename the current generated field/references and
extend the offline registration fixture for legacy-name migration. Preserve all
resource identities and media. Tests/analyzer remain manual; formatting/syntax only.

Failure repair — 3 November 2026: completed Karoo job failed publication because
sorting added publication metadata to the live catalogue during transcription.
Goal: recover completed artifacts without another transcription, freeze catalogue
bytes per future run, report concise stage/exit/log-path errors, and scroll long
progress-dialog content with actions accessible. Preserve all publication checks,
prior editions and failed-run evidence. Done when snapshot hashes and existing
checkpoints protect recovery, focused regressions are supplied and formatting /
syntax checks pass. Flutter tests, worker suites and media jobs remain manual.

Repair implemented: each new run saves catalogue-snapshot.yaml and publication
hash-checks/uses those frozen bytes. Legacy runs retain the original guard.
Worker reports stage, exit code, diagnostic and full-log path. Progress dialog
uses AlertDialog scrolling; Close remains outside scroll content. Added long-error
widget and noisy-progress worker regression coverage. Tests not run; ZSH and
embedded Python syntax checked, Dart formatted.

Recovered run 715c283a5ddf43688e18aa52f8163c0c: removed only newly added date fields
from live YAML to reconstruct original bytes, proving the saved SHA-256 before
writing its missing snapshot. Verified all six completed checkpoints, performed
publication and package/export checks, then activated its immutable edition in
the idle worker's library. Original failed job retained; recovery.json records
activation and previous index. 728 passages, 13,954,243 audio bytes; no download,
encoding, transcription, alignment, test suite or app launch repeated.
Restart worker and app to load new worker code and refreshed library. Manual
acceptance: recovered Karoo plays and opens transcript; future prepare uses frozen
metadata; failed details scroll on narrow windows and Close stays reachable.

## Optional contextual refinement — 4 November 2026

Add “Refine using ChatGPT” directly below Model, selected by default. Selecting
Prepare authorises one synchronous GPT-5.4 mini review of the local index and
selected passage contexts, up to US$0.50 for that job; show the limit and data
sharing notice before starting. No actual paid job is authorised during this
implementation. Existing CLI defaults remain local-only.

Use the existing private Mac-side key file; report missing configuration before
expensive preparation. Older workers must not silently ignore the option. After
local indexing, refine before activation, record request/usage/proposals and
conservative cost reservation, never retry or substitute models automatically.
Validate all candidate IDs, category choices, literal evidence IDs, normalization
lengths and merges. Preserve all categories, human decisions, original transcript
and uncertain suggestions. Species should be recategorized, not rejected merely
because it is not a person. Keep paper/article mentions independent.

Failure/budget overflow retains the new local index and clearly reports that
refinement did not complete. Cancellation terminates the helper and never retries
an ambiguous billable request. Display an indeterminate refinement stage and
actual cost/results or warning at completion. Source metadata snapshots allow
unreviewed saved suggestions to update while preserving user edits. Add offline
request/response validation, cancellation/budget/safe-apply tests and UI/transport
coverage. Use existing focused-test/analyzer authorization; no live API, media
processing, app launch, Git mutation or dependency installation.

## Reopen externally resumed preparation — 5 November 2026

Goal: make progress reachable when a job resumes in the worker after the app
has stopped polling its old failed status. Add a macOS toolbar Preparation
progress icon independent of locally cached job state. Open the root progress
modal immediately, refresh the worker's current job, restart normal polling for
an active run, and keep errors visible. Backgrounding the modal must not stop
processing. Guard the shared progress opener against duplicate rapid clicks.
Use the same opener for the existing active-job banner. Episode Prepare also
refreshes current status before deciding whether to show options or progress.

Acceptance: failed → external resume → toolbar click displays live alignment;
latest status is fetched with no new preparation request; one modal after rapid
double-click; close/background keeps job running; connection errors remain visible.
No worker restart or active-job interruption. Created no new production files;
modified controller, dialog and catalogue shell. Added controller discovery and
modal regression cases to preparation_flow_test.dart. No tests, analysis, build,
app launch or Git actions run. Verification pending. From flutter_app run
`flutter test test/features/preparation/preparation_flow_test.dart` and
`flutter analyze`, then hot reload and manually reopen/background progress.
Record date/tester/environment/results. Phase not applicable. Suggested commit:
`Restore progress access for externally resumed preparation jobs`.

Compiler fixture correction — 6 November 2026: three newly added progress tests
omitted PreparationJob's required nullable remainingSeconds argument. Added
remainingSeconds: null to those fixture constructors, preserving the production
contract (unknown estimate). No other constructor sites omit it. Focused Flutter
rerun remains manual: `flutter test test/features/preparation/preparation_flow_test.dart`.
No Flutter tests, analysis, builds or launches run during this correction.
Suggested commit: `Supply unknown remaining time in preparation progress fixtures`.

## Mobile transcription disabled — 9 November 2026

Goal: iOS and Android must not initiate transcription. Episode pages display:
“Please use your desktop or laptop for transcription. You can read existing
transcripts on this device.” Keep existing Transcript navigation and loading
unchanged. Guard the preparation dialog before worker access, and reject native
mobile backend job submissions before registry reads or requests. Desktop
preparation remains unchanged.

Implemented in episode detail, shared preparation platform policy, dialog and
HTTP backend. Added iOS/Android dialog tests; desktop preparation flow tests now
explicitly select macOS. Acceptance: mobile explanatory message, no preparation
job, existing bundled/server transcript readable, desktop preparation intact.
Formatted Dart only; tests, analysis, builds and launches not run. See
outputs/mobile-transcription/README.md for verification. Not a numbered phase.

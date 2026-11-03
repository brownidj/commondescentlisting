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

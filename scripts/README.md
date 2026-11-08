# Episode preparation (zsh)

## Install CD List on the iPhone

From project root, run `zsh scripts/run_ios_release.zsh`; from flutter_app, use
`zsh ../scripts/run_ios_release.zsh`. Unlock the phone first. The script generates
Flutter release configuration, builds with Xcode outside iCloud Drive, installs
and launches the release app on David's paired phone. Later launches use the Home
Screen icon. Logs are retained under outputs/ios-release/. See
[iOS deployment notes](../docs/IOS_DEVICE_RUN.md) for options and troubleshooting.

## Prepare episode data

Entry point: `scripts/prepare_episode.zsh`. Shared stages are in
`scripts/episode_pipeline/`; keep them together. Run from any working directory.
No per-episode script copies are needed.

From the CD List project root, for an episode not yet packaged:

```zsh
zsh scripts/prepare_episode.zsh 55
```

Use the actual episode wanted instead of 55. Episodes 54, 72 and 208 already have
packages; this script refuses to overwrite them. It does not adopt historical
per-episode runs as its own checkpoints.

The default transcription model is **medium.en**, cached in this project at
`work/whisper/models/ggml-medium.en.bin`. Its SHA-256 is
`cc37e93478338ec7700281a7ac30a10128929eb8f427dda2e865faa8f6da4356`.
App registration is **enabled by default**. Use `--no-register` to produce the
package/exports without changing Flutter registration; `--register` remains
accepted for explicit use. Rebuild the app to include newly registered assets.

On another machine, copy the model there, supply `--model`, or set `WHISPER_MODEL`.
The previously used small.en model remains cached and can be selected explicitly.
Opus/libopus produces the 16 kbps audio; the Whisper model produces the transcript.
Changing the transcription model does not change the audio bitrate.
No credentials or paid transcription API.
Use an English-compatible whisper.cpp model. The recognition prompt defaults to
the podcast and catalogue episode title; override with `--prompt 'names, terms'`.
This provides recognition context without applying post-transcription corrections.

## Dependencies

macOS; `whisper-cli`, `ffmpeg` (libopus), `ffprobe`, `jq`, `curl`, `shasum`,
Swift/AVFoundation and `afconvert`. Uses the existing WhisperX/PyYAML/torch/certifi
environment at `work/whisperx-trial/venv/bin/python` and cached English wav2vec2
model at `work/whisperx-trial/models/wav2vec2_fairseq_base_ls960_asr_ls960.pth`.
Set `EPISODE_PYTHON` to use a compatible alternative environment. Model, tool and
pipeline hashes/versions are recorded; changed settings refuse to resume.
Dependencies/models must already be installed; the script does not install them.
The medium.en file requires about 1.5 GB of storage, plus the alignment model
and roughly a GB of temporary PCM for a long episode.

## Processing and outputs

1. Resolve exactly one episode in saved `data/episodes.yaml`; no RSS refresh.
2. Capture and fingerprint its HTTPS enclosure in ignored work storage.
3. Encode mono 48 kHz Opus at 16 kbps target, constrained VBR.
4. Decode/check Apple and FFmpeg sample counts and seven paused native seeks.
5. Transcribe the final Opus decode with whisper.cpp, English, eight threads.
6. Create stable passage IDs and align them with WhisperX against that same Opus.
7. Check bounds, identities and payload hashes; retain uncertainty flags. Publish
   the complete package, exports and report. Preserve other existing packages.
8. Update the Flutter resource registry and pubspec asset folders by default
   (skip with `--no-register`). Save originals in registration-backups/. No new app dependencies.
9. Remove this run's regenerable WAVs. Keep the original until explicit disposal.

- Report, raw transcript, logs, checkpoints and alignment evidence:
  `outputs/episodes/<stable-key>/`.
- Listener TXT/JSON/VTT/SRT: `docs/transcripts/episode-<number>-<title>.*`.
- Playback package: `flutter_app/assets/episodes/<stable-key>/`.
- Source download: `work/episode-pipeline/<stable-key>/source.mp3`.

TXT has one passage per line; JSON preserves IDs, original edit reference times
and aligned timings. Package manifests fingerprint audio and every payload.
Transcription is **Machine transcribed; not reviewed.** Acoustic flags are listed
in README.md; absence of flags does not certify names or wording. Publisher section
markers remain catalogue timestamps, not acoustically verified boundaries.
Watch progress with the transcription.log or alignment.log in the run directory.

## Resume and maintenance

After interruption, use the same episode and `--resume`; saved model/prompt are
reused unless explicitly overridden. Changed config, code, tool versions or
completed-stage bytes stop the run rather than mixing editions.

```zsh
zsh scripts/prepare_episode.zsh 55 --resume
```

Completed runs verify the published package/exports and register by default
with that command. Previously started runs retain their saved transcription model;
the new medium.en default applies to new runs. Changed pipeline code still causes
the existing configuration guard to stop; archive/review an old run explicitly
before reprocessing, rather than editing its checkpoints. Registration uses a project-wide lock, backups and atomic file
replacements; rerunning repairs an interruption between the two source writes.
Review the diff before rebuilding. An existing hand-maintained registration is
never silently replaced. Script-generated Dart may be formatted manually.

Each episode has a `.processing-lock/owner.txt` in its work directory. Concurrent
runs of the same episode stop. If killed without cleanup, confirm the recorded
PID is no longer processing before manually removing the stale lock. The same
rule applies to `work/episode-pipeline/.registration-lock/`. Processing different
episodes is technically possible but likely slower under shared CPU/RAM load.

Original deletion is a separate operation; run only after listening/device
acceptance. It verifies the published package and original hash before deletion:

```zsh
zsh scripts/prepare_episode.zsh 55 --discard-original
```

The source URL/hash and a disposal receipt remain. Source disposal does not erase
provenance. Automatic redownload or replacement of completed editions is not
implemented: advertising may change the recording. Preserve/archive the existing
edition and plan a new explicit edition rather than reusing its timing identity.
Uncertain words, Nudge and local edits are never automatically rewritten.

## Manual verification

No live pipeline, test suite, Flutter analysis/build/app or Git operation was run
when this script was created. The shared alignment algorithm comes from the
previous successful episode workflow, but this generalized wrapper needs acceptance.

Run the offline fixture regression first (no audio download or app launch):

```zsh
zsh scripts/tests/episode_pipeline_smoke.zsh
```

It covers changed-checkpoint rejection, recovery after package rename, corrupted
published-audio rejection, and idempotent registration preserving existing assets.
Then prepare one new episode and check default medium.en/default registration,
explicit --model/--no-register overrides, uninterrupted completion, interrupted-stage
resume, refusal after changing a completed artifact/config, flags and transcript
exports, and exact correspondence between registered hashes and the manifest.
Keep the original through acceptance. Record environment/date/tester/results.

After default registration (or explicit `--register`), from flutter_app:

```zsh
flutter analyze
flutter test test/data/episode_package_repository_test.dart test/data/episode_package_manifest_test.dart
flutter run -d macos
```

Check transcript search, passage play/edit, highlighting, skips and persisted Nudge
at the start/middle/end, then repeat on iOS. The pipeline never executes those
commands itself and does not certify scientific names or audible synchronization.

## Preparing from the app

The macOS app can now request this pipeline through the authenticated local
worker `scripts/episode_preparation_server.zsh`. Start it once per session, then
use **Prepare episode** on the selected episode. The worker uses isolated jobs,
model downloads on selection, measured progress and atomic local-library
activation. It does not edit the app source or replace bundled assets; completed
local editions are available without rebuilding. See
`docs/IN_APP_EPISODE_PREPARATION.md` for setup, re-preparation choices and tests.
The existing command-line defaults remain medium.en plus bundle registration.

## Optional ChatGPT review from the app

The app's Model dialog includes **Refine using ChatGPT**, enabled by default.
Local transcription and indexing run first; the worker then calls
`refine_episode_index.zsh` with one synchronous review capped at US$0.50.
Uncheck it for local-only preparation. Configure the private Mac-side credential
with `configure_indexing_key.zsh`; no credentials enter the Flutter app. No retry
or model substitution is automatic. Review failures/budget overflow retain the
local index and produce an explicit completion warning. CLI `prepare_episode.zsh`
continues to default to local-only indexing. See
`docs/IN_APP_EPISODE_PREPARATION.md` for privacy, costs, usage records and restart
instructions. Offline helper regressions: `zsh scripts/tests/index_refinement_test.zsh`.

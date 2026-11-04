# Prepare episodes from the macOS app

The app keeps its sandbox. A local worker runs the zsh pipeline outside it.
User selected this architecture (option 1). The worker requires this project's
existing WhisperX environment, whisper-cli, ffmpeg and native macOS tools.

## Start and connect

Rebuild/restart the macOS app after installing this code. From flutter_app, start
the worker in a separate Terminal and keep it running:

```zsh
../scripts/episode_preparation_server.zsh
```

In the app, select/highlight an episode and click **Prepare episode**. On the
first connection, choose the CommonDescentListing project folder. This grants
access to its local connection file; credentials are saved in the app's own
Application Support directory. Future app launches reconnect while the worker
is running. You do not need to run preparation commands manually for each episode.

Preparation is a macOS authoring feature. It does not launch desktop tools on iOS.
The existing iOS bundled-audio/transcript reader is unchanged; transferring newly
prepared local editions to iOS remains outside this increment.

## Choices

- New episode: choose any supported model, with medium.en selected initially.
- Already prepared: **Re-prepare episode?** asks Yes/No before starting anything.
- Yes → **Use larger model** retains the recording and offers only higher model
  ranks than the recorded original model. It does not encode retained Opus again.
- Yes → **Redownload** captures a fresh original, encodes it and transcribes it.
  It initially selects the current model; you may choose another.
- If the current model is unknown or already largest, the larger-model option
  is disabled. Legacy Karoo model identification is recovered only when its raw
  transcript/TXT provenance matches the baseline's recorded original TXT hash.

Available choices: tiny.en, base.en, small.en, medium.en, large-v3-turbo and
large-v3. Missing models show download sizes and are fetched when selected,
using the pinned revision and SHA-256 values in scripts/episode_pipeline/models.json.
No bulk download or paid transcription API. Larger models use more resources;
model rank expresses model size, not a promise that every word improves.

The original download remains outside the playback package. Choosing a larger
model keeps the retained audio; new unprepared episodes can also reuse an existing
cached original. Redownload deliberately ignores those caches.

## Estimates and progress

Before every job the chooser shows an estimated processing range, including
uncached model download time. It uses the known recording duration when available,
or explicitly assumes two hours. The worker refines duration after capture.
Estimates are planning ranges, not measured benchmarks for every model/Mac.
Timings/download assumptions are centralized in the model catalogue.

The progress dialog shows current stage, measured stage percentage, elapsed time
and estimated remaining time. Encoding uses ffmpeg output timestamps;
transcription uses whisper.cpp progress/caption times; alignment uses completed
WhisperX chunks. Download progress uses bytes written. Checks and publication
use an indeterminate bar rather than a fabricated percentage.

**Continue in background** closes the dialog while the job continues. A preparation
banner offers progress again. **Cancel preparation** terminates the active process
group, including encoder/transcriber children. Keep the worker running; stopping
its Terminal stops its job. Errors retain logs and the previous active edition.

## Packages and corrections

Every job has a new ID; its candidate package is immutable and isolated. Only after
full pipeline success and payload hash verification does an atomic local index
activate it. The old edition remains on disk. Newly prepared audio/transcripts are
usable immediately without rebuilding or changing the Flutter source registry.
This local-library registration is separate from CLI default bundle registration.

- Local index/packages: work/episode-preparation/library.json and packages/.
- Model cache: work/whisper/models/.
- Job state: work/episode-preparation/jobs/.
- Logs/raw/aligned exports: outputs/episodes/<key>/runs/<job-id>/.
- Temporary audio/downloads: work/episode-pipeline/<key>/runs/<job-id>/.
- Listener copies: docs/transcripts/episode-<number>-<title>-<job-id>.*.

Audio identity and transcript timing always switch as a pair. Switching editions
stops the previous recording; an editor bookmark never resumes an old timestamp
in a changed recording. New transcript editions have separate correction journals
under Application Support/transcript-edits/editions/<job-id>/. Original journals
and previous corrections remain intact; they are not guessed onto new passages.
The text remains machine-generated and unreviewed; timing flags require listening.

## Worker boundaries and recovery

The worker binds only to 127.0.0.1:8765, requires a random per-project token,
rejects browser origins, restricts request sizes/paths, and exposes no arbitrary
command endpoint. Episode GUID/model choices are validated against saved data.
Audio serving supports HEAD and byte ranges for precise native seeking.
The app permits local networking; sandbox entitlements are unchanged.

One worker job runs at a time. A project-wide worker file lock prevents a second
instance. Restart detects unfinished jobs and refuses to overlap a surviving child
process. Otherwise it marks the interrupted job failed and keeps the old index.
Job failures are not automatically resumed or silently changed to another model.
Retry starts a fresh isolated edition. Partial model downloads can resume.

Do not delete old packages/journals or edit checkpoints to force a failed job
through. Shared pipeline changes can make historical CLI --resume refuse a config;
that safeguard still applies. The app creates new per-job configurations.

## Manual acceptance

Not run by the assistant: worker launch, live preparation, model downloads,
Flutter analysis/tests/build/run, audible playback or iOS acceptance.
Syntax-only checks and Dart formatting were performed. From project root:

```zsh
zsh scripts/tests/episode_pipeline_smoke.zsh
zsh scripts/tests/preparation_worker_test.zsh
```

From flutter_app:

```zsh
flutter analyze
flutter test test/features/preparation test/features/episodes/playback_controller_test.dart test/data/episode_package_repository_test.dart
flutter run -d macos
```

Start the worker separately. Check connection/reconnection; first-time model
selection; No causing no job; larger-only choices; redownload retaining selected
model; accurate stage progress; cancelling during download/encoding/transcription;
background operation; failure retaining the old package; successful immediate
play/read/search; edited-journal preservation; and skips/highlighting at the start,
middle and end. Check starting a replacement while an editor is open. Record
macOS/device, date, tester and outcomes. Large models may need substantial memory.
The existing strict alignment validator can still reject ambiguous timings; the
UI reports failure rather than publishing an invalid replacement.

## ChatGPT index refinement

In the preparation dialog, **Refine using ChatGPT** appears below **Model** and is
on by default. Prepare authorises a synchronous contextual index review after
local transcription/alignment/indexing, with a US$0.50 maximum per job. The dialog
shows an indicative US$0.10–0.30 estimate (Marsupials cost US$0.156); actual cost
depends on candidate/context/output size. Selected passage contexts and candidate
names/categories are sent to OpenAI; audio is not uploaded. Suggestions still need
review, and this does not discover names missed by local extraction.

The API key stays on the preparation Mac in ignored
`work/indexing-trial/openai-api-key`. Configure it using
`scripts/configure_indexing_key.zsh`; never paste it into Flutter settings or commit
it. If configuration is missing, turn refinement off to prepare locally, or
configure the Mac first. Old workers require a restart before the option can run.

The worker invokes `scripts/refine_episode_index.zsh` with pinned settings in
`scripts/indexing_trial/refinement.json`: GPT-5.4 mini snapshot, reasoning disabled,
Structured Outputs, `store: false`, one synchronous request, no automatic retries
or model substitutions. The US$0.50 guard reserves a conservative input-byte bound
(including cache-write overhead) plus the full configured output allowance before
any request. A request too large for that budget is skipped with a visible warning;
there are no hidden additional calls. Pricing settings are based on official
model documentation checked 4 November 2026 and require maintenance if rates change.

Validate complete candidate coverage, allowed categories, supplied evidence IDs,
normalization sizes and merge consistency before applying. Low-confidence or
uncertain suggestions remain unchanged; confirmed/rejected metadata and human
edits survive app refresh. Duplicate headings use the existing persistent merge
rules. Publication metadata is not fabricated or externally verified.

If review fails, the new audio/transcript/local index remains usable and completion
reports the failure. Cancellation retains the previous active edition; a started
request may still incur usage, so its reservation/actual usage is retained and
shown. No automatic retry occurs. Reports and request/response/usage files are in
`outputs/episodes/<key>/runs/<edition>/refinement/`. The completion dialog displays
cost and held-for-review counts after a successful review. CLI preparation remains
local-only by default; this checkbox applies to app preparation.

After installing this change, stop the existing preparation worker with Ctrl-C,
start it again with `zsh scripts/episode_preparation_server.zsh` from the project
root, and restart/relaunch the app from updated source. No model/media processing
or paid request is necessary to enable the option.

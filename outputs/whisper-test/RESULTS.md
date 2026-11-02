# whisper.cpp trial results

Completed 31 October 2026 on David's Mac. Full local transcription succeeded;
no paid API was called. This was the single episode trial explicitly requested
by David, not an application change or a catalogue transcription run.

## Random selection

Episode 208 — The Karoo Supergroup, published 4 January 2025 in the feed's
timezone. Selected uniformly using Python secrets.randbelow from all 391 saved
RSS entries; zero-based index 77. Recorded in episode.json.

Source: https://commondescentpodcast.podbean.com/e/episode-208-the-karoo-supergroup/

Actual downloaded audio duration: **1:49:03.509**. Source MP3: 93,396,730 bytes.
The saved feed's published duration was 6,543 seconds.

## Runtime and cost

| Measurement | Result |
| --- | --- |
| whisper.cpp | 1.9.5, Homebrew binary |
| Model | small.en, 487,614,201 bytes; publisher SHA-256 verified |
| Machine | Apple M4 Pro, 24 GiB RAM |
| Acceleration | Metal GPU confirmed by runtime log |
| CPU threads | 8; default beam/best-of settings |
| Input | 16 kHz, mono, signed 16-bit PCM WAV |
| Full transcription elapsed time | **141.45 seconds — 2 minutes 21 seconds** |
| Speed | **46.26× real time** |
| Processing per audio hour | About 1.30 minutes |
| Peak resident memory | About 1.87 GiB, reported by /usr/bin/time |
| Transcription API charges | **US$0** |

The timed portion includes model loading/inference and transcript output, but
excludes software/model/audio downloads and audio conversion. Electricity,
internet access, storage and human review were not priced or measured.

At this episode's measured rate, the saved catalogue's 698.46 audio hours would
take approximately **15.1 hours of transcription** on this Mac. This is a
single-episode extrapolation, not a guarantee. It excludes downloads, conversion,
review, interruptions, retries, and a potentially slower higher-quality model.

## Outputs and checks

- episode-208-karoo.txt — raw uncorrected text, approximately 16,633 words.
- episode-208-karoo.vtt — WebVTT captions for a future timed transcript view.
- episode-208-karoo.srt — standard timestamped subtitles.
- episode-208-karoo.json — 1,032 transcript segments with timestamp offsets.
- timing.txt, results.json and environment.json — measured evidence.
- run_trial.zsh — reproducible zsh invocation for this same episode.

The command exited successfully. All four transcript outputs are non-empty;
the VTT header is present; JSON segment starts are ordered; segment end times
are within the audio duration. Captions run from 00:00:00 to 01:49:02.680,
ending about 0.83 seconds before the audio finishes. These checks establish
file integrity and time coverage, not recognition or alignment accuracy.

The raw result spells **Karoo as Karu**, occurring 68 times, and contains no
correctly spelled Karoo. Terms such as Permian, Triassic and Lystrosaurus appear.
This is a clear reason to review scientific names and consider a vocabulary
prompt or a stronger model before processing the catalogue. Outputs have not
been silently corrected. There was no reference transcript, word-error-rate
measurement, speaker-identification validation or listening-based accuracy test.

## Repeating the trial

The retained model, source MP3, converted WAV and runtime log are under the
chat workspace's work/whisper-test directory. The zsh script reuses those files,
or downloads the selected source/model if absent. It overwrites this episode's
transcript and timing outputs when rerun. It does not reselect an episode.

With whisper-cli and ffmpeg installed, run:

```zsh
zsh "/Users/david/Library/Mobile Documents/com~apple~CloudDocs/PyCharm projects/CommonDescentListing/outputs/whisper-test/run_trial.zsh"
```

The trial executed this script's conversion, timing and transcription commands.
The later additions for conditional downloads/checksum reuse were not rerun as
a full transcription; equivalent downloads and checksum validation were executed
separately during setup. Final script syntax was checked with zsh -n.

## Installation notes

Homebrew installed whisper.cpp 1.9.5 plus its dependencies. It installed ggml,
llama.cpp, SDL3 and OpenSSL 4, and upgraded libomp, ca-certificates and
sdl2-compat. ca-certificates and OpenSSL 4 reported post-install warnings,
including on one retry; those warnings remain unresolved. whisper-cli ran
successfully for this complete local trial despite them.

Homebrew temporarily changed the default OpenSSL command from version 3 to 4.
The original OpenSSL 3.6.3 links were restored afterwards; OpenSSL 4 remains
installed for the new dependencies. whisper-cli --version was rechecked after
restoring the links. No application files, tests or Git state were changed by
this trial. Trial outputs have been moved to CommonDescentListing/outputs/.
The downloaded model, audio and runtime log remain in the original chat's
work/whisper-test directory; run_trial.zsh retains that location for reuse. Set
WHISPER_TRIAL_WORK to use a different scratch directory.

## Suggested next step

Review a few passages against the audio, particularly scientific names and
segment boundaries. If acceptable, design an incremental transcription pipeline
that saves each episode's output once. No bulk run or Flutter integration has
been started. A higher-quality model comparison would be a separate trial.

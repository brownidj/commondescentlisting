# Karoo compression listening comparison

Created and run on 2 November 2026, macOS 27.0.1, FFmpeg 8.0, Apple AudioToolbox
via afconvert. This is a short-sample comparison; a default has not been selected.

Open `index.html` in a browser. Choose an excerpt, press Play, then switch formats.
Switching preserves approximately the same position. The page works locally
without a server, fetch requests, packages, or an internet connection.

## Outputs

Three 60-second excerpts, each with five versions (15 files in `samples/`):

| Excerpt | Original episode clock | Content |
|---|---|---|
| Opening | 00:00:00–00:01:00 | Intro, music and voices |
| Science | 00:54:50–00:55:50 | Geological discussion and scientific names |
| Closing | 01:48:00–01:49:00 | Voices and outro music |

Each lossless FLAC reference preserves its decoded MP3 excerpt. It does not
recover quality already lost in the original MP3. All candidates use that same
60-second mono, 44.1 kHz, 16-bit PCM input, not another compressed candidate.
There is no gain adjustment, denoising, speed change or removal of content within
an excerpt. HE-AAC uses Apple's encoder, CBR and maximum codec-quality setting;
Opus uses libopus, constrained VBR, audio mode, compression level 10 and 48 kHz.

## Measured sizes and projections

Original complete MP3: **93,396,730 bytes (89.1 MiB)**, duration 6543.509388 seconds.
It was already mono; downmixing provides no additional saving for this episode.

| Candidate | Mean size per minute | Estimated full episode | Estimated saving |
|---|---:|---:|---:|
| HE-AAC 24 kbps | 188,620 bytes | 19.6 MiB | 78.0% |
| HE-AAC 32 kbps | 248,786 bytes | 25.9 MiB | 70.9% |
| Opus 16 kbps | 127,451 bytes | 13.3 MiB | 85.1% |
| Opus 24 kbps | 186,510 bytes | 19.4 MiB | 78.2% |

These are extrapolations from three separate one-minute files, including their
per-file overhead. A single complete encode would have different overhead and
may have different average Opus bitrate. No full-episode candidates were encoded.

## Verification actually performed

- All 15 files encoded and decoded successfully through both FFmpeg and Apple's
  afconvert. Native decoding returned exactly 2,646,000 mono frames at 44.1 kHz
  (60.000 seconds) for every file. Source excerpt frame counts also matched.
- Native afinfo identified HE-AAC and mono in the format list. FFmpeg identifies
  HE-AAC, but reports two channels for these Apple implicit-SBR files and a
  60.139683-second container duration. Its decoded output has 2,650,048 frames
  (60.091791 seconds). Apple's decoder correctly handles priming/remainder and
  produces the intended mono 60 seconds. These differing measurements are
  retained in `probes/`, rather than treated as equivalent.
- Opus container duration is 60.006500 seconds, including its pre-skip;
  FFmpeg and Apple both decode exactly 60 seconds. FLAC also decodes exactly.
- The SHA-256 of each delivered file is in `manifest.json`; source edition is
  `05920194f6cb7411cb69bfc8e1aafb348a7d84b25607104bc40f4631d134036b`.
- Tool versions, container probes, decoded-frame probes and native format reports
  are saved in `probes/`; `summary.tsv` contains the compact measured data.

Decode counts do **not** establish acoustic alignment, listening quality, browser
support, Flutter/AVPlayer support or seek precision. No Flutter tests, analysis,
builds, app launches or automated test suites were run. No tests were added.

## Listening acceptance

Use the same headphones and volume. Compare the science excerpt first, especially
consonants and scientific names; check whether the voices acquire metallic or
watery artifacts. Then compare music in the opening/closing. Decide which is the
smallest format comfortable for a complete episode. HE-AAC 24 kbps is the initial
Apple-platform candidate, subject to listening and native player/seek review.

The app continues using its existing source. Existing code, source MP3, transcript
assets, timing, calibrations and edit journal were not modified. Choosing a
default and preparing the full-episode audio edition require the next instruction.
Before integration, validate acoustic timing and seeks against the final recording;
do not copy an old edition's calibration or assume container duration proves sync.

## Reproduction

`create_samples.zsh` is the complete zsh launcher. It runs from any directory,
requires ffmpeg with libopus, ffprobe, jq and Apple's afconvert/afinfo, and checks
the exact source edition before encoding. It refuses to replace an existing
published sample set. To repeat, move `samples/`, `probes/`, `manifest.json`,
`summary.tsv` and `comparison-data.js` together to an archive folder first.

From this directory in zsh:

```zsh
/bin/zsh ./create_samples.zsh
```

Intermediate PCM remains under `work/audio-compression-trial/`; deliverables are
under `outputs/audio-compression-trial/`. No original audio was deleted. Created
files include this report, the comparison page/data, launcher, manifest, TSV,
15 samples and their probe reports. The plan is
`docs/plans/AUDIO_COMPRESSION_TRIAL.md`; no application code was changed.

Status: sample generation and decoder checks complete; listening and device
acceptance pending. Phase: not applicable. No Git mutations were performed.
Suggested commit description: `Add reproducible Karoo audio compression comparison`.

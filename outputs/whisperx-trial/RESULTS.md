# WhisperX Karoo trial and Nudge persistence

2 November 2026. Authorised alignment trial completed; native listening review
and Flutter test execution remain pending. No listener timing files were replaced.

## Nudge saves its adjustment

The production path is `_nudgeTranscript` → `TranscriptEdits.setSyncOffset` →
conditional journal write → staged file/flush/atomic rename. The in-memory offset
updates only after a successful save. Existing failed-save/conflict handling
protects edits and leaves an unsuccessful adjustment unapplied.

Read the installed macOS journal directly: offset **-30,501 ms**, a 500 ms advance
from the previous -31,001 ms; **nine text revisions** intact. This demonstrates
the setting is on disk, not just transient widget state. See
`nudge-persistence-check.json`. Each episode's calibration is saved separately;
original passage timestamps remain unchanged. This does not imply syncing settings
between macOS and iOS.

Extended the existing disk-store regression in
`flutter_app/test/features/episodes/transcript_edits_test.dart`: save +500 ms,
verify JSON on disk, reload through a new store, preserve text/history, subtract
500 ms and reload again. Dart formatted; Flutter tests/analysis were not run.
No production save code needed changing.

## Actual alignment results

WhisperX **3.8.6**, default English **WAV2VEC2_ASR_BASE_960H**, CPU, four threads.
Python 3.13.0, Torch 2.8.0; isolated pinned environment under project
`work/whisperx-trial/venv`. Full package versions: `requirements-lock.txt`.
Model fingerprint: `model-checksum.txt`. No paid API calls.

Input: first **120 seconds**, 16 kHz mono PCM, **32 existing reviewed passages**.
The launcher reads applicable saved text corrections, but none of the nine local
revisions affected this clip. Text and passage IDs were preserved. This is forced
alignment of existing text, not a new transcription.

The first successful pass independently aligned padded passage windows. It
returned times for all passages but flagged 26 for overlaps, low scores or window
edges. Short repeated phrases could be assigned to neighbouring speech. Evidence:
`run-20261102T014856Z-gKxnJC/`. Its 144.273 seconds includes model downloading/load.

The second pass aligned consecutive passages together in <=30-second chunks,
with 1.5-second window padding, then mapped words back by exact text sequence.
Evidence: **`run-20261102T015228Z-vqD14p/`**. Cached-model run: **9.086 seconds**;
peak resident memory about **2.53 GB**. All **32 passages** received timed words.
Original asset and installed local journal were byte-for-byte unchanged during
the run. Performance is for this short CPU trial, not a full-episode estimate.

Examples, seconds in the captured clip:

| Passage | Original span | WhisperX span |
|---|---|---|
| 1 — opening announcement | 0.000–19.760 | 0.580–2.962 |
| 2 — Hello Will | 19.760–20.760 | 19.693–20.214 |
| 3 — Hello David | 20.760–21.760 | 20.294–20.834 |
| 16 — It is so cool | 69.160–70.200 | 69.133–69.994 |

These are algorithm outputs, not manually verified ground truth. The opening
announcement result suggests the original first cue included a long non-word
interval, consistent with why anchoring that cue at its stored zero was misleading.

**Six passages remain flagged:** 12/13, 18/19 and 27/28 overlap across chunk
boundaries. Word scores are model scores, not calibrated correctness probabilities.
We have not silently clipped/merged overlaps or adopted timestamps. The app expects
ordered, non-overlapping cues; these candidates require review/reconciliation.
See `TIMING_COMPARISON.md`, the run's `comparison.tsv`, `alignment.json`, and raw
chunk-level output `chunks.json`. Input/provenance and execution metrics are saved
as `input.json` and `summary.json`.

## The advertising constraint

A fresh download prefix decoded to **exactly the same first 120 seconds** as the
original audio used for Whisper transcription. Both WAV SHA-256 values:
`18566f33d2876caa92dcc45ae08b7c66acf4a3c27ed9422e93ddbcc3da785b1b`.
The MP3 header reports 6543.509388 seconds; David's player reported 6573.675:
a **30.165612-second difference**. The new capture therefore does not reproduce
the longer advertised version. The full fresh MP3 download was stopped after
enough prefix audio for this trial; only the derived clip is a deliverable.

These timestamps belong to this fixed audio clip. Do not apply them directly
to a differently advertised stream or reset the saved -30.501-second calibration.
Further alignment should use a fixed audio version and retain its identity;
stream-specific advert mapping/calibration remains a separate problem. Duration
difference alone does not locate every insertion. See `audio-provenance.json`.

## Reproduction and review

All launcher/setup scripts are ZSH. `run_alignment.zsh` embeds the Python library
API call because WhisperX's CLI retranscribes; no Python shell scripts or Bash
launchers are used. The environment's CA bundle is explicitly selected to fix the
Python.org installation's HTTPS certificate issue without disabling verification.
The initial failed attempt's log remains in `run-20261102T014804Z-U92DiC/`.

From the project root:

```zsh
zsh outputs/whisperx-trial/setup.zsh
zsh outputs/whisperx-trial/run_alignment.zsh
```

`extract_clip.zsh` can recreate the clip from an explicitly supplied captured
MP3 when the clip does not already exist. It refuses to overwrite the trial audio.
Models/download scratch stay in ignored project work; results stay in outputs.

For Nudge regression checks, from flutter_app:

```zsh
flutter test test/features/episodes/transcript_nudge_test.dart test/features/episodes/transcript_edits_test.dart
flutter analyze
```

Recommended next step: listen-check the clip against the candidate boundaries,
especially flagged pairs; then trial a middle/late chunk from the same captured
audio. Record tester, date, platform and pass/fail observations. Preserve originals,
IDs and timing provenance when deciding whether to adopt a full-episode alignment.

Files created: this report, plan, ZSH setup/extract/run launchers, pinned
requirements, PCM clip, provenance/persistence snapshots, model checksum,
comparison document and per-run inputs/logs/results. Modified only the existing
disk-store regression test plus trial plan updates; no production app code, assets,
journals or Git mutations. Trial status: executed and results saved; accuracy and
native app adoption unverified. Suggested commit: Add WhisperX alignment trial and strengthen Nudge persistence coverage

Package references: [WhisperX](https://github.com/m-bain/whisperX),
[alignment implementation](https://github.com/m-bain/whisperX/blob/v3.8.6/whisperx/alignment.py).

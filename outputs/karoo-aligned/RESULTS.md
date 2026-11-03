# Full Karoo aligned playback

Completed implementation and full alignment on 2 November 2026. This supersedes
the short WhisperX trial and the old approximately 31-second stream correction.
Native application verification and human listening checks remain pending.

## What listeners get after rebuilding

The in-app player now plays the captured fixed recording for Episode 208 on both
macOS and iOS. The exact same MP3 was used for the full WhisperX alignment. It is
bundled as `flutter_app/assets/audio/episode-208-karoo.mp3` (about 89 MiB), adding
that amount to the app's source/assets. Playback, replay while editing and bookmark
restoration all resolve to this asset. No network fallback silently substitutes
an advertised stream if loading this asset fails. Other episodes keep streaming.
Apple Podcasts remains external and does not use this matched recording.

The transcript loader applies a separate timing asset to all **1032 passages**,
retaining their IDs, original reviewed wording and original timing provenance.
The original reviewed transcript asset is unchanged. Nine local text revisions
were included during acoustic alignment and remain in the existing journal.
Runtime edits load against their original passage/timing references, so replacing
the display timing does not invalidate text history.

Calibration is now scoped to the audio identity. The old advertised-stream
adjustment (last read -30.501 s) is ignored for the fixed recording, whose initial
offset is **zero**. That old value is not deleted. The next Nudge saves the fixed
edition's offset separately, preserving the old value under `legacy-stream`.
Subsequent fixed-edition nudges survive reloading. Original transcript timestamps
are retained as `source_start_ms` / `source_end_ms` in aligned exports.

The timing diagnostic report includes the audio identity. Its panel identifies
the fixed edition, and export wording distinguishes aligned timings from original
timestamps. JSON includes the active Nudge adjustment; VTT/SRT retain the aligned
base timings (the export dialog explains this).

## Actual processing evidence

- WhisperX 3.8.6, English WAV2VEC2_ASR_BASE_960H, CPU, four threads.
- **1032/1032 passages** have word timings; original IDs/text preserved.
- Duration **6543.509 seconds** (1:49:03.509).
- Processing **312.227 seconds** (about 5 minutes 12 seconds).
- Neighbouring text context used in 302 chunks; four boundary pairs jointly
  re-aligned. **No remaining overlaps**, no artificial shared display boundaries,
  no original-timestamp fallback passages, ordered positive spans within the audio.
- One low-score passage, **1025**, near **1:48:06**, remains explicitly flagged for
  listening review. It is not silently represented as human-verified accuracy.
- Original transcript and installed journal were byte-for-byte unchanged by the run.

Audio SHA-256:
`05920194f6cb7411cb69bfc8e1aafb348a7d84b25607104bc40f4631d134036b`.
The app's fixed-edition identity and alignment manifest use this hash. Published
asset hashes and original transcript hash are in `asset-checksums.txt`. The timing
asset is byte-identical to the processing output. Publication rechecked audio and
source transcript hashes, complete ID coverage, baseline text and positive ordered
timings before writing exports. No algorithm can guarantee every boundary to the
millisecond; these are acoustically aligned timings, not a full human audit.

Examples in the fixed recording:

| Passage | Aligned start | Aligned end |
|---|---|---|
| 1, opening announcement | 00:00:00.580 | 00:00:02.962 |
| 12, Karoo introduction | 00:00:42.384 | 00:00:49.688 |
| 16, “It is so cool” | 00:01:09.129 | 00:01:09.989 |
| 441 | 00:43:29.629 | 00:43:35.491 |
| 1032, closing sentence | 01:48:50.205 | 01:48:55.446 |

## Saved deliverables

In this output directory: full timing manifest, raw chunk and word-level results,
boundary repairs, comparison TSV, summary, logs, hashes, and listener-ready
`episode-208-karoo-aligned.{json,txt,vtt,srt}`. TXT/VTT/SRT copies also reside in
`docs/transcripts/`. The standalone JSON uses the nine local corrections present
at processing time; the app continues loading future local edits from its journal.

ZSH reproduction launchers:

```zsh
zsh outputs/karoo-aligned/align_episode.zsh
zsh outputs/karoo-aligned/publish_transcripts.zsh
```

They use the previously installed isolated environment in work/whisperx-trial and
its cached model. The embedded Python is the package's library API, launched by
ZSH; no Bash commands/scripts were introduced. Package pins are retained in the
preceding trial's requirements-lock.txt. Reproduction does not edit the local journal.

## App integration and focused coverage

New app files:
- lib/data/episode_audio.dart: authoritative fixed audio identity/source.
- lib/models/transcript_alignment.dart: strict complete timing overlay validation.
- assets/audio/episode-208-karoo.mp3 and assets/transcripts/episode-208-karoo-alignment.json.
- test/features/episodes/aligned_playback_test.dart.

Modified app files:
- lib/data/bundled_transcripts.dart and lib/models/episode_transcript.dart.
- lib/services/playback_controller.dart, native_audio_engine.dart,
  transcript_edits.dart, transcript_export.dart, transcript_timing_diagnostics.dart.
- lib/features/episodes/episode_detail.dart, transcript_page.dart,
  transcript_editor_dialog.dart, transcript_timing_dialog.dart.
- lib/widgets/playback_bar.dart, playback_keyboard_controls.dart; pubspec.yaml.

Created docs/plans/KAROO_ALIGNED_PLAYBACK.md and this report/output artifacts.
No files removed. Regression coverage: complete asset loading and ID/text/source
timing preservation; invalid edition, missing cue and overlap rejection; legacy
edits and old offset isolation; fixed-edition Nudge persistence; export round trip;
fixed-source play/seek/editor restoration. Existing episode behavior stays covered
by the playback and transcript test suites.

Executed: full alignment and publication integrity checks; Dart formatting.
Not executed: Flutter tests, Flutter analysis, macOS/iOS builds or app launches,
following AGENTS.md's manual-verification default. No Git mutations.

From flutter_app, stop the old running app and run the following in zsh:

```zsh
flutter analyze
flutter test test/features/episodes/aligned_playback_test.dart test/features/episodes/transcript_edits_test.dart test/features/episodes/transcript_nudge_test.dart test/features/episodes/playback_controller_test.dart test/features/episodes/transcript_page_test.dart
flutter run -d macos
```

A full rebuild/restart is needed to package the new audio and timing assets.
Hot reload alone may keep the previously loaded advertised stream and old context.
On iOS, rebuild and run the updated app on the device in the same way as earlier.

Manual acceptance (record tester/date/platform/pass/fail): choose Audio player,
open Karoo, confirm advert-free fixed recording and zero initial adjustment in
diagnostics; seek passages at the start/middle/end and check highlighting; confirm
all nine saved edits remain; Nudge ±500 ms, leave/reopen, verify persistence; edit
and audition a passage then confirm bookmark restoration; review passage 1025;
check another episode still streams normally. macOS and iOS require native checks.

Status: full alignment and implementation complete; automated structural evidence
recorded; native runtime and acoustic listening acceptance unverified. Unphased
work. Suggested commit: Match full Karoo alignment to fixed audio and scope saved timing adjustments by edition

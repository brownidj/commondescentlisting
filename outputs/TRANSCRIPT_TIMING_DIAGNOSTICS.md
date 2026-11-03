# Transcript timing measurement tool

Implemented 2 November 2026. Unphased work. Runtime verification pending.

## How to collect useful measurements

1. Choose Audio player in Settings and open an episode's transcript.
2. Press the stopwatch icon, “Transcript timing diagnostics”, in the toolbar.
3. Use Play/Pause and the seek slider in the panel to listen near the beginning,
   middle and end. Seek a little before a clear passage boundary. Listen to locate
   it rather than assuming the highlighting is correct.
4. Enter the passage number you intend to measure. Check its preview text. This
   selects a measurement target without changing edit selection or audio position.
5. While audio is playing, click “Mark spoken start” at that passage's FIRST words.
   Do not click halfway through the passage. Do not press Sync during sampling.
6. Collect at least three different passages far apart in the episode, preferably
   more, repeating any ambiguous observation. Press “Copy report” and paste the
   JSON into the chat for comparison. Closing/reopening this panel keeps samples;
   leaving the transcript page or restarting the app loses them unless copied.

The panel shows raw audio position, saved offset, adjusted clock, calculated
highlight passage/bounds, playback state, audio duration and last transcript end.
Duration differences alone are not evidence of drift (audio may have outros etc.).

Each observation records the stored start/end, audio clock at click, saved offset,
highlighted passage ID, audio duration, UTC recording time and passage wording.
All report durations are integer milliseconds. A positive raw difference means
the words begin later in the audio than the stored timestamp. The calibrated
residual adds the saved offset: zero means the current calibration aligns the
measurement. The report describes both conventions explicitly.

Compare observations in audio-time order: roughly constant raw differences suggest
an offset; a progressive change suggests drift; an abrupt change suggests a local
timing error or audio-content difference. Aligned timestamps with a visibly wrong
highlight need further clock/display investigation. The tool does not automatically
classify these patterns, recognise speech, or eliminate human reaction-time error.
An initial offset may be wrong even when individual timestamp errors also vary.

Marking never seeks, pauses, writes transcript text or saves calibration. It is
disabled while paused, busy, buffering, failed, dragging the seek slider, using a
different episode/output, or selecting an invalid passage. Playback controls seek
or pause only when explicitly used. Episode replacement waits until the panel
closes so it cannot dispose the active transcript edit model during measurement.

## Implementation and verification

Created:
- flutter_app/lib/services/transcript_timing_diagnostics.dart
- flutter_app/lib/features/episodes/transcript_timing_dialog.dart
- flutter_app/test/features/episodes/transcript_timing_diagnostics_test.dart
- docs/plans/TRANSCRIPT_TIMING_DIAGNOSTICS.md
- this handover document

Modified flutter_app/lib/features/episodes/transcript_page.dart to wire the
toolbar action, retain session observations by episode, and guard editing and
episode replacement while diagnosing. No files removed or Git mutations.

Coverage supplied for difference/residual sign and JSON fields; capture of live
clock without playback/calibration changes; reopening retention; disabled marking
for paused/buffering/no-episode/invalid target. Dart formatting completed.
Tests, analysis, builds and app launches were not run, under project AGENTS.md.

From flutter_app, run in zsh:

```zsh
flutter analyze
flutter test test/features/episodes/transcript_timing_diagnostics_test.dart test/features/episodes/transcript_page_test.dart
```

Manual acceptance: on macOS/iOS, verify the live clock, target entry, seek/pause,
first-word marking, disabled states, narrow-layout scrolling and copied JSON.
Confirm Sync offset and corrections remain unchanged; close/reopen retains samples.
Record tester, date, platform and pass/fail results. Completion evidence still
requires these checks and the focused tests; timing diagnosis also requires real
listening samples. Copy report uses the clipboard rather than creating files.

Suggested commit: Add transcript timing diagnostics and observation report

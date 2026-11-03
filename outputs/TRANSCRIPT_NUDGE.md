# Transcript timing nudge — 2 November 2026

Implemented “‹ Nudge ›” beside the player's passage number, visible only when a
transcript reader's route is active. Left subtracts 500 ms from the saved offset,
retreating the transcript clock/highlight; right adds 500 ms, advancing it. Audio
position and playing/paused state are unchanged. Text and cue times are unchanged.
For example, -31.001 s becomes -31.501 s with left, or -30.501 s with right.

The existing journal save/conflict handling persists each adjustment. Disable the
controls while busy, editing, exporting, diagnosing, in conflict, for another
episode/output, or when the next step exceeds the supported calibration limit.
Registration follows the existing route-aware transcript Edit action and is
removed when leaving the reader. A failed save leaves the adjustment unchanged
and shows an error. Buttons also work with paused audio.

Modified:
- flutter_app/lib/services/playback_controller.dart (optional reader nudge actions)
- flutter_app/lib/features/episodes/transcript_page.dart (guarded offset save)
- flutter_app/lib/widgets/playback_bar.dart (same-row controls)
- docs/plans/IN_APP_AUDIO_PLAN.md (acceptance and status)

Created flutter_app/test/features/episodes/transcript_nudge_test.dart and this
report. No files removed. Widget coverage checks 500 ms signs, passage crossing,
saved/reloaded offset, unchanged audio, failed writes, phone layout and route
visibility/disposal. Dart formatting completed; tests, analysis, builds and app
launches not run, under AGENTS.md. No Git mutations. Unphased work.

Run from flutter_app in zsh:

```zsh
flutter analyze
flutter test test/features/episodes/transcript_nudge_test.dart test/features/episodes/player_sync_button_test.dart
```

Manual check: play a transcript on macOS/iOS, nudge both ways and confirm the
highlight shifts while speech continues uninterrupted. Reopen the transcript to
confirm persistence; navigate elsewhere to confirm controls disappear. Check
phone width and an offset at its limit. Record tester/date/platform/results.
Implementation complete, verification pending; actual alignment still depends on
the listener's chosen offset and the audio stream's advertising/timestamp accuracy.

Suggested commit: Add persistent half-second transcript nudge controls to player

# Flutter review follow-up verification

This checklist covers the transcript-page reuse, export-timing disclosure,
visible-route playback ownership, and native/performance checks. No results are
recorded here; fill in the environment and outcome fields when performing the
checks.

## Environment and commands

- Date/time:
- Flutter/Dart versions:
- Device or simulator and OS version:
- Audio output selected:
- Tester:
- Result and notes:

From `flutter_app/`, run the focused regressions and then the full suite and
analyzer when authorized:

```zsh
flutter test test/features/episodes/transcript_page_test.dart test/features/episodes/transcript_editor_test.dart test/features/episodes/playback_interactions_test.dart test/features/episodes/playback_controller_test.dart
flutter analyze
flutter test
```

## Manual behavior checks

- [ ] Replace an episode in an existing transcript page; confirm its title,
  passage text, search query, and selected passage all belong to the new episode.
- [ ] Delay the first transcript load, replace the episode, and allow the newer
  load to finish first; confirm a later completion from the old episode cannot
  replace the current page.
- [ ] Open two transcript routes; confirm the player-bar edit action belongs to
  the top route, becomes unavailable when that route cannot edit the loaded
  episode, and returns to the previous route after popping.
- [ ] Export VTT/SRT and JSON after applying a playback timing offset; confirm
  the warning says VTT/SRT retain original timestamps and JSON carries the
  app-specific offset. Cancel and confirm no export occurs, then continue and
  inspect the generated files.
- [ ] On supported devices, play, pause, seek, switch output, trigger an audio
  failure, and verify the visible player state reflects the audible state.
- [ ] Test the Apple Podcasts handoff on iOS/macOS, including both an exact
  episode mapping and a search fallback; record whether the external app opens.

## Performance profiling

- Use a representative episode with a long chapter list and profile playback
  updates on a representative device in profile mode.
- Record device/OS, episode and chapter count, test duration, frame timings,
  janky-frame count, and any CPU/allocation observations.
- Compare chapter-list scrolling and playback before considering caching or
  other optimization; no performance defect or improvement is claimed here.
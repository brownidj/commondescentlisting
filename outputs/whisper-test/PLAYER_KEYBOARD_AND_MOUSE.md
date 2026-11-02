# Player keyboard and passage mouse controls

Implemented the requested controls:

- **Space** pauses/resumes the in-app player when an episode is available. Held
  key repeats do not toggle repeatedly, and modifier combinations are ignored.
  Space remains available for typing in search and transcript-edit fields.
- **Left-click/tap a passage** starts audio from its calibrated start. Player
  segment chips also start/resume at that segment, including when paused.
- **Right-click a passage** highlights it for editing without changing the audio
  position or play/pause state. Long-press provides the equivalent on touch devices.
  The player's pencil edits this selection. A selection notice and Clear selection
  action distinguish it from the playing passage. Paging is held during selection
  so the edit target stays still; clearing it, left-clicking, changing the search
  or text mode, or closing the editor restores normal following.
- **Below the slider:** Passage N of total replaces elapsed/duration text. This
  always refers to the audio, including calibration, rather than an edit selection.
  Missing transcript data and timing gaps show a truthful unavailable/between
  passages message. Loaded transcript metadata remains usable after navigating
  away from its reader. Time is still available on the slider tooltip.

Modified playback controller/bar, transcript page, transcript model and shared
time lookup; added playback_keyboard_controls.dart. Updated the existing playback
widget test for chapter chips starting audio, and added playback_interactions_test
for Space/typing, left/right clicks, Edit selection, chapter playback and passage
metadata/calibration/episode isolation. Updated the in-app audio plan. No files
removed, transcript data edited or Git actions performed.

Dart formatting ran. Tests, Flutter analysis, builds and native runs were not run
under the project's manual verification instructions. From flutter_app:

```zsh
flutter analyze
flutter test test/features/episodes/playback_interactions_test.dart test/features/episodes/playback_widget_test.dart test/features/episodes/transcript_editor_test.dart test/features/episodes/transcript_follow_test.dart
```

Manual checks: Space with body/button focus, held Space, search typing and edit
typing; right-click and player Edit while audio continues; clear selection and
left-click from pause; click a player segment from pause. Check passage count
through seeks, calibration, gaps and navigation. Repeat using touch/long-press and
an external iPad keyboard where available. Record environment/date/tester/results
before declaring native behaviour verified. Implementation complete; verification
pending. Suggested commit: `Add player keyboard and transcript mouse controls`.

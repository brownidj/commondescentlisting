# Transcript follows playback

Implemented 1 November 2026. Verification pending.

While the in-app Audio player is playing the episode shown in the transcript,
the reader automatically keeps its current timed passage visible and highlighted.
This applies to opening the transcript mid-episode, normal progress, forward and
backward seeks, resume, and scrolling away from the playing passage. Pause audio
to browse the transcript freely; resume to follow again. Original and reviewed
text share the same passage times, including local edits.

With a search active, the current playing passage is included alongside matching
passages even when its words do not match. A notice explains this, and the result
count still counts only genuine search matches. The query stays intact. Pausing
returns to matching passages alone; resuming shows and follows the active passage.

The list uses two lazy slivers anchored around the target index, so a seek can
reach a far-away passage with variable text height without rendering all earlier
passages or guessing their heights. Follow positioning happens after layout;
manual scrolling returns to the playing cue. A passage taller than the viewport
aligns at its start. No extra package dependencies were added.

This uses the existing machine-generated passage timestamps, not word-level or
newly corrected alignment. Before the first cue, between timed cues and at/after
the final end, no invented active passage is shown. Playback of another episode
does not drive this reader. Apple Podcasts does not provide its playback position
to this app; use the Audio player for synchronisation.

## Changes and verification

Added `flutter_app/lib/features/episodes/transcript_follow.dart`,
`flutter_app/lib/features/episodes/transcript_passage_list.dart`, and
`flutter_app/test/features/episodes/transcript_follow_test.dart`.
Updated the transcript reader, its existing search widget regression test (pause
before browsing back to the header), and the reviewed-transcript plan. No transcript
data edited, no files removed, and no Git mutations.

Added timing-boundary and widget coverage for mid-episode opening, natural
progress, distant forward/backward seeks, lazy rendering, manual scrolling,
search excluding the playing cue, clearing search, pause/resume and another episode.
Dart formatting was run. Tests, Flutter analysis, builds and app launches were
not run, following the project's manual verification instructions.

From the project's `flutter_app/` directory:

```zsh
flutter analyze
flutter test test/features/episodes/transcript_follow_test.dart test/features/episodes/transcript_page_test.dart test/features/episodes/transcript_editor_test.dart
flutter run -d macos
```

Manual checks on macOS/iOS: start Episode 208 well into the discussion, open its
transcript, watch passage transitions, seek far forward/backward, scroll away,
pause and browse, then resume. Repeat with a search that excludes the current
passage, original text, local corrections, narrow/landscape layouts and enlarged
text. Check replay while editing and reopening the reader after navigation.
Record environment, tester, date and results before declaring native behaviour
verified. Status: implementation complete; verification pending. Phase: authorised
follow-up. Suggested commit message: `Keep transcript scrolled to playing audio`.

# Player Sync control placement

Moved **Sync** from the transcript toolbar to the far right of the persistent
player's segment-button row. The segment area occupies the remaining width and
scrolls horizontally; Sync stays pinned at the right on desktop and phone layouts.
It toggles the same transcript timing controls as before. Saved adjustments,
measured passage anchoring and timing calculations are unchanged.

The transcript registers its action with the shared player after loading and
unregisters on disposal. Registration ownership supports nested reader routes.
Sync is disabled if the player's selected episode differs from the transcript;
it is removed when no reader action remains registered. The separate **Sync to
audio now** action remains in the passage editor.

Modified playback_controller.dart, playback_bar.dart and transcript_page.dart,
the existing transcript follow test harness, and the in-app audio plan. Added
player_sync_button_test.dart covering placement, timing-panel toggle, narrow
layout, wrong-episode disabling and cleanup after navigating back. No files
removed, transcript data edited or Git actions performed. Dart formatting ran;
tests, Flutter analysis, builds and launches were not run under the project's
manual verification default.

From the project's flutter_app directory:

```zsh
flutter analyze
flutter test test/features/episodes/player_sync_button_test.dart test/features/episodes/transcript_follow_test.dart test/features/episodes/playback_widget_test.dart
```

Manual check: open a transcript with its episode selected; verify segment buttons
on the left and Sync at the far right; toggle its timing panel, resize to phone
width, scroll the segments and navigate back. Verify no stale callback/Sync action
after leaving the reader. Status: implemented; automated/native verification
pending. Suggested commit: `Move transcript Sync to the player segment row`.

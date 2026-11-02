# Revised transcript Edit and Sync actions

This supersedes the earlier player Sync placement and timing panel.

- The far right of the player's segment row now contains one **Edit highlighted
  passage** pencil icon, with no text label. It opens the text editor for the cue
  highlighted at the exact time of the click. Playback advancing afterward does
  not switch which passage the open editor edits.
- Every transcript passage has a **Sync passage N to audio now** icon in place of
  its pencil. Press it at the beginning of the words you hear. It immediately
  saves that passage's alignment to the current audio clock, using the existing
  persistent episode offset. No editor opens and audio does not seek or pause.
- The player Sync button, old adjustment panel, and duplicate Sync action inside
  the text editor have been removed. Original timing/text, saved corrections,
  history and export are retained. Sync success/failure appears in a message.
- Sync requires that episode to be selected in the in-app player. Both actions
  are disabled during incompatible player/save states; Edit is unavailable with
  no highlighted passage, in a timing gap, or on a different selected episode.
  Actions unregister on leaving the reader. Segments remain scrollable on the
  left while the player pencil remains pinned on the right.

Changed playback_controller.dart, playback_bar.dart, transcript_page.dart and
transcript_editor_dialog.dart, the in-app audio plan, and three existing widget
test files. Tests now cover direct row sync without seek/dialog/text revision,
correct highlighted editing at click time, cancel/save/replay/history/export,
icon placement, narrow layout, episode guards and route cleanup. The earlier
manual timing-panel widget scenario was replaced by direct passage sync coverage;
unit calibration and persistence coverage remains. No files removed, transcript
data changed or Git mutations performed.

Dart formatting ran. Tests, Flutter analysis, builds and native runs were not run,
following the project's manual verification instructions. From flutter_app:

```zsh
flutter analyze
flutter test test/features/episodes/player_sync_button_test.dart test/features/episodes/transcript_editor_test.dart test/features/episodes/transcript_follow_test.dart
```

Manual checks: sync the passage actually heard and confirm playback continues and
highlighting catches up; press the player pencil and confirm the dialog's passage
number matches the highlight. Check the editor stays on that passage as playback
advances; save/cancel, restart, try a different episode, and inspect narrow/large
text layouts. Implementation complete; automated/native verification pending.
Suggested commit: `Move passage editing to player and sync directly from transcript`.

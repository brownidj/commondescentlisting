# Separate playback and edit selection

Implemented 1 November 2026; verification pending.

The passage at the audio position keeps the secondary theme highlight and an
“Audio position” label. A selected edit passage has a tertiary highlight, border,
and “Selected for editing” label. When the same passage serves both purposes it
keeps the audio fill and adds the edit border and both labels.

Right-click/long-press selects only; left-click still plays from that passage.
Edit captures the listening position and playing state before pausing. Replay in
the dialog auditions the selected passage. Save, Cancel and dialog dismissal
restore the saved position, resuming only if audio was playing before Edit.
Restoration waits for an outstanding Replay load. Closing the player or changing
its episode/output prevents restoration from restarting an unwanted session.
An unloaded preview stays unloaded unless Replay is used. Audio failures remain
reported by the player's existing error handling.

Modified: playback_controller.dart, transcript_page.dart,
transcript_editor_dialog.dart, playback_interactions_test.dart, and
docs/plans/IN_APP_AUDIO_PLAN.md. No files removed. This report is new.

Coverage added: independent highlights and selection without seeking; pause on
Edit; Replay then Cancel restores a playing bookmark; Replay then Save restores
a paused bookmark; silent-preview restoration; restoration during pending Replay.
Dart formatting completed. Tests, analysis, builds and app launches were not run.

Run from the project's flutter_app directory in zsh:

```zsh
flutter analyze
flutter test test/features/episodes/playback_interactions_test.dart test/features/episodes/transcript_editor_test.dart test/features/episodes/player_sync_button_test.dart
```

Manual verification: on macOS and iOS, play a passage, select a different passage
for editing, and confirm both highlights remain visible without audio movement.
Open Edit and confirm audio pauses. Replay the selected passage, then Save or
Cancel; confirm the original position and playing state return. Repeat starting
paused, and confirm it stays paused after closing Edit. Check both highlights
when selecting the audio-position passage. Record tester/date/platform/results
before marking verified. Native audio/network behavior remains unverified.

Phase: not applicable. Suggested commit message:
Separate transcript edit selection and preserve listening position during edits

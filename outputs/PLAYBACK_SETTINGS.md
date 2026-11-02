# Playback settings

Implemented 31 October 2026 as an authorised follow-up to IN_APP_AUDIO_PLAN.md.

Use the Settings gear on the main page to select **Audio player** or
**Apple Podcasts**. The selection is saved privately on the device and restored
on startup. Audio player is the default. Changing it stops in-app audio; a
failed save retains the previous selection and displays a message. Selecting
Apple Podcasts hides the in-app controls. External Podcasts playback is
controlled by Podcasts; switching back cannot stop audio already playing there.

Episode pages, including those opened from News, now have a single **Play**
button using this choice. The source-page button remains. In-app segment seeking
is available with Audio player, not Apple Podcasts. Unmatched Apple episodes
retain the existing title-search fallback. The general **Original news summary**
expansion row was removed; the selected news item's context summary and the
underlying YAML data are retained. Review guidance points to the episode page.

Added services/playback_preferences.dart and widgets/playback_settings_dialog.dart.
Modified app.dart, catalogue_shell.dart, episode_detail.dart, playback_bar.dart
and playback_controller.dart. Added playback_preferences_test.dart; updated
Apple handoff, storage and episode-browser test expectations. No files removed.
No Git actions performed. Suggested commit:
`Add saved playback settings and unify episode Play action`.

Verification: Dart files formatted. Tests, analysis, builds and launches not
run for this change under the manual-verification default. Implementation is
complete; native acceptance remains pending. Run in zsh from flutter_app:

```zsh
flutter analyze
flutter test
flutter run -d macos
```

On Mac and iPhone, change each setting, restart to confirm persistence, play an
episode from Episodes and News, and confirm the in-app controls only appear for
Audio player. Check a missing Apple episode opens search, audio failures remain
recoverable, and switching away from active in-app playback stops it. Confirm
the general summary row is absent and the source-page button still opens.

# Skip alignment follow-up

2 November 2026. Goal: preserve transcript alignment/follow after forward/back
seeking without changing Nudge or audio edition. Unphased implementation complete;
verification pending.

Two relevant paths were found in local source inspection:

- Fixed audio used just_audio's convenience asset loader. Its default progressive
  source does not request AVURLAssetPreferPreciseDurationAndTimingKey. The existing
  native plugin already requests zero seek tolerance; changing tolerance is not
  needed. Fixed sources now explicitly set DarwinAssetOptions with precise timing
  enabled before loading/indexing the MP3. This may increase initial load time.
- A right-click edit selection suppresses transcript page following. An explicit
  seek did not release it, allowing audio to move while the page remained held.
  Successful position commands now increment a seek revision; the reader clears
  that hold during a dependency update. Ordinary audio progress/Nudge do not clear
  selection; editor audition and diagnostic workflows keep their own behavior.

These are source-based fixes; the reported native audible mismatch has not been
reproduced by launching the app, so neither cause is claimed conclusively proven.
No extra guessed offset, timestamp rewriting, new audio version or journal edits.

Created lib/services/playback_audio_source.dart (source configuration helper),
test/features/episodes/skip_alignment_test.dart, and this report. Modified
lib/services/native_audio_engine.dart, playback_controller.dart,
lib/features/episodes/transcript_page.dart and docs/plans/KAROO_ALIGNED_PLAYBACK.md.
No files removed or Git mutations.

Coverage supplied: precise Apple option on the actual fixed-source construction
path; unchanged HLS detection; only successful seeks change seek revision; actual
Forward 30 seconds and Back 15 seconds buttons update visible passage/highlight,
release edit selection, keep one loaded fixed source, keep playing, and leave the
saved 500 ms Nudge journal byte-for-byte unchanged. Dart formatting completed.
Tests, analysis, builds and app launches were not run, following AGENTS.md.

From flutter_app in zsh:

```zsh
flutter analyze
flutter test test/features/episodes/skip_alignment_test.dart test/features/episodes/transcript_follow_test.dart test/features/episodes/aligned_playback_test.dart test/features/episodes/playback_interactions_test.dart
flutter run -d macos
```

Fully stop/restart playback/app so the recording is reloaded with precise timing;
hot reload alone leaves the already-loaded native source using its old options.
Manual acceptance: play Karoo, skip +30 repeatedly and back -15 at early/middle/
late positions, confirm audible words match the highlighted passage and saved
Nudge is unchanged. Repeat after selecting a different passage for editing, and
while paused. Check editor replay/restoration separately. Record tester/date,
platform and pass/fail results on macOS and iOS. If mismatch persists, collect a
diagnostic mark immediately after a skip and a corresponding normal-playback mark
to distinguish native seeking from local transcript timing errors.

Suggested commit: Preserve transcript following and request precise fixed-audio seeking

Analyzer follow-up, 2 November: added braces in TranscriptPage.didUpdateWidget
and the aligned_playback_test timing loop; removed the redundant episode-null
comparison in PlaybackBar's chapter button. These are the three reported findings;
no behavioral changes or new tests/files. Formatted the three files. Assistant
did not run analysis/tests. Rerun flutter analyze and the focused commands above.
Acceptance is no repeat of the three diagnostics; verification pending David's
rerun. Suggested commit: Resolve transcript and player analyzer findings

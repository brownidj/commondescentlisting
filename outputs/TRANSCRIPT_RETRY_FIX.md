# Transcript retry assertion fix

2 November 2026. Unphased bug fix; implementation complete, verification pending.

Goal and scope: remove the reported Future-returning setState assertion during
transcript retry and episode replacement without changing loading behavior.

Changed flutter_app/lib/features/episodes/transcript_page.dart: use a block
callback to assign the transcript Future without returning it. The asynchronous
load still starts outside setState. The same method serves retry and episode
replacement, so this addresses both reported assertion paths.

Changed flutter_app/test/features/episodes/transcript_page_test.dart: existing
retry and episode-replacement tests now check for exceptions immediately after
the triggering actions, in addition to their existing loaded-content and stale
load checks. No new test file or removed files. This report is new.

Acceptance: retry displays the transcript without an assertion; replacing an
episode resets search and ignores stale load completion without an assertion.
Done when the affected tests and manual retry/replacement checks pass.

Dart formatting completed. Tests, analysis, builds and app launches were not run,
following AGENTS.md. From flutter_app, run in zsh:

```zsh
flutter test test/features/episodes/transcript_page_test.dart
flutter analyze
```

Manual checks: retry a failed transcript load and switch between episodes with
transcripts. Record tester, date, platform and pass/fail results. Remaining risk:
the fix has not yet been verified by running Flutter. No Git mutations performed.

Suggested commit: Fix Future-returning transcript reload setState callback

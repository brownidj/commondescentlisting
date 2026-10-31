# Phase 3 — Episode Catalogue and Detail Verification

Status: implementation delivered; manual verification pending. Phase 4 is not started.

## Changes and boundaries

Created the episode controller, responsive browser, detail view, segment cards, and external-link service under `flutter_app/lib/`. Modified the catalogue shell and `pubspec.yaml`. Added controller/widget coverage in `flutter_app/test/features/episodes/episode_browser_test.dart`; updated setup and plan documentation. No files removed. Python, canonical YAML, and the bundled dataset were not changed.

Episodes are searched by title or episode number (case-insensitive, trimmed). All/Numbered/Side episodes filters preserve source order. Selection uses GUID rather than title. Wide content areas (at least 900 logical pixels after the navigation rail) show a list/detail split; narrower content shows detail with Back to episodes. Search/filter state remains when returning and when switching the Episodes/News destinations.

Detail shows each source segment separately, including both discussion parts, nullable times, raw summary expansions, and automatic-split notices. An explicit zero time displays `00:00:00`; a missing time is unavailable. News-section times are labelled separately. Missing news records are described as not listed, not as proof there was no news.

Source links use pinned `url_launcher: 6.3.3` in external-application mode. Reference: https://pub.dev/packages/url_launcher. Only a valid HTTP(S) `sourceUri` from the data model yields an enabled action. Link failure produces a recoverable message. Real browser/plugin behaviour requires manual macOS verification.

Separate news browsing/search remains Phase 4; the News destination explains that news is currently available within episode details. YAML import/persistence remains Phase 5.

## Commands for David

From `flutter_app/`, in zsh:

```zsh
flutter pub get
flutter analyze
flutter test test/features/episodes/episode_browser_test.dart
flutter run -d macos
```

Run `flutter pub get` to resolve the new launcher dependency and update the existing lockfile. Restart the application after adding the native plugin; hot reload alone is insufficient.

Tests added cover GUID-based selection with matching titles, title/number search, filters/source order, narrow Back navigation and retained search, wide selection across resize, raw summary expansion, distinct news/item times, multiple discussion parts, explicit zero time, unsafe links, external-launch failure, and empty-versus-no-match states.

Tests/analysis/builds/app launches run by the assistant: **None — manual verification requested.** Dart sources were formatted only.

## Manual checklist

Record tester, date, macOS/Flutter versions, window dimensions/text scale, Pass/Fail, and notes/screenshots.

| Check | Expected behaviour | Result |
| --- | --- | --- |
| Dependency resolution/analysis | Both complete successfully; retain the updated lockfile. | Pending |
| Focused tests | Controller/widget tests pass. | Pending |
| Offline list | Bundled episodes appear without networking, in source order. | Pending |
| Search | Search title with mixed case/outer spaces and a fractional/suffixed episode number; clear restores the filter's source order. | Pending |
| Filters | All, Numbered and Side episodes change the list correctly. | Pending |
| No matches | Unmatched query has an informative empty state. | Pending |
| Grouped detail | Selecting an episode opens the correct GUID and all its source segments without merging titles. | Pending |
| Episode 255 | News starts at `00:05:25`; individual headline times stay unavailable; discussion Part 1 is `00:47:35`, Part 2 is `01:16:05`. | Pending |
| Original summary | Expand the original news summary; it matches YAML and automatic-split notice is visible. | Pending |
| Narrow navigation | Detail replaces list; Back returns to retained search/filter. | Pending |
| Wide layout/resize | List/detail coexist; selection survives resize and switching Episodes/News. | Pending |
| Source links | Valid page opens in the system browser; unavailable/unsafe link has no broken action. Opening failure is reported without losing catalogue state. | Pending |
| Accessibility | Tab/keyboard activation works; enlarged text and short/narrow windows remain readable and scrollable. | Pending |
| Error handling | Existing malformed-data error and retry flow remains functional; restore bundled data after any temporary edits. | Pending |

Outstanding: no runtime, widget-test, analysis, or native-plugin result is claimed. Layout/accessibility, platform link opening, and compatibility of the new dependency remain pending David's local checks. macOS is still the provisional initial target. Do not proceed to Phase 4 without authorisation.

Suggested commit after review: `Add searchable episode catalogue and responsive segment details`.

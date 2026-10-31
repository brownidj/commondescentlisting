# Phase 4 — News Catalogue and Shared Search Verification

Status: implementation delivered; manual verification pending. Phase 5 has not started.

## Changes

Created `flutter_app/lib/features/news/news_browser.dart`, `news_controller.dart`, shared matching policy `lib/features/catalogue/catalogue_search.dart`, and `test/features/news/news_browser_test.dart`.

Modified the shell to display NewsBrowser, the episode controller to use shared matching, and episode detail/segment cards to identify the selected news item. Updated setup and plan documentation. No files removed or dependencies added. Python and both YAML snapshots are unchanged.

News search matches headline, episode title, and episode number using the same trimmed, case-insensitive matching policy as episode search. Episode search continues to match title/number; news search additionally matches the source headline. Clearing search restores all source news records in order, including repeated headlines within and across episodes. No new headline text is inferred from summaries.

Each news row shows episode context, available time information, and review status. Untitled records appear as “News section.” Whole-section timestamps are never presented as individual-headline times. Selecting a row opens its GUID-linked episode detail with a selected-headline banner, its item position within that episode's news records, selected-item original-summary access, and a highlighted source segment in the ordered segment list. The detail route's Back action returns to retained news search/scroll state. Episode browsing retains its separate state when switching destinations.

## Commands for David

From `flutter_app/`, in zsh:

```zsh
flutter analyze
flutter test test/features/news/news_browser_test.dart test/features/episodes/episode_browser_test.dart
flutter run -d macos
```

If dependencies have not been resolved since Phase 3, first run `flutter pub get`. No dependency resolution, analysis, tests, builds, or application launch were run by the assistant. Sources were formatted with `dart format` only.

Tests created cover shared title/number search semantics, case and surrounding whitespace, repeated headlines within/across episodes, source-order restoration, exact selected GUID/session item, Back retaining search, selected raw-summary access, news-section time labelling, untitled records, and empty/no-match states. Existing episode tests should be rerun because they now use shared matching and the augmented detail view.

## Manual checklist

Record tester, date, OS/Flutter versions, window dimensions/text scale, result, and notes/screenshots.

| Check | Expected result | Result |
| --- | --- | --- |
| Analysis and focused tests | Complete successfully. | Pending |
| Offline news list | Every source `News` record is available; discussion records do not appear as news. | Pending |
| Search fields | Headlines, episode titles, fractional/suffixed numbers, case differences and surrounding spaces work. | Pending |
| Clear search | Restores source order and duplicate records without deduplication. | Pending |
| Duplicate selection | Repeated headlines reach their correct GUID and item, even within the same episode. | Pending |
| Selected context | Detail identifies selected headline and its episode-news position; matching segment is highlighted in the ordered list. | Pending |
| Original summary | Selected-item expansion shows original text; episode-level summaries remain available. | Pending |
| Times | For episode 255, `00:05:25` is labelled the news-section start; individual unknown headline times remain unavailable. | Pending |
| Review notice | Automatically split/incomplete records are explained without claiming verification. | Pending |
| Back/state | Back returns to the previous news query/position; switching Episodes/News preserves each destination's state. | Pending |
| Empty/no-match | No news in the dataset and an unmatched search have different useful messages. | Pending |
| Accessibility/layout | Short/narrow and wide windows, enlarged text, keyboard focus and activation remain usable; content scrolls. | Pending |
| Episode regression | Episode filters, details, separate discussion parts and source links still behave as Phase 3 specifies. | Pending |

Outstanding: runtime, navigation, layout/accessibility and tests await local verification. Selected-item identity is based on source position within this snapshot and is not a durable bookmark. Local YAML replacement/persistence remains Phase 5. No Git changes were made.

Suggested commit message after review: `Add searchable news catalogue and exact episode-item navigation`.

## Follow-up fix — summary/scroll state collision

David reported `type 'double' is not a subtype of type 'bool?'` from Flutter's Expansible state. Inspection of the installed SDK confirmed that both scroll offset and expansion flag use the nearest PageStorageKey path. The original summary tile used only a ValueKey, and the selected-item summary had no storage key, allowing either to reuse the detail list's offset entry.

Changed `episode_detail.dart` to give both summary tiles distinct PageStorageKeys and a fresh, separately named detail-scroll key. Added `episode_detail_storage_test.dart` covering scroll/dispose/remount and independently restored expansion state for episode and news-entry paths. No tests or app launch were run by the assistant.

From `flutter_app/`, run:

```zsh
flutter analyze
flutter test test/features/episodes/episode_detail_storage_test.dart test/features/episodes/episode_browser_test.dart test/features/news/news_browser_test.dart
flutter run -d macos
```

Stop the previous app completely and relaunch. Scroll episode 255 down and back, expand/collapse original summaries, leave/reopen the episode, and repeat by opening a news item. Confirm expansion and scroll restoration no longer throw a type error. The fix awaits those checks; Phase 4 verification remains pending.

Suggested commit message: `Separate summary expansion storage from episode scroll offsets`.

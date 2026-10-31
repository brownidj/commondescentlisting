# Phase 5 — YAML Import, Persistence and Reset

Status: implementation delivered; manual verification pending. Phase 6 is not started.

## Changes

Created bounded local-source helpers, a private file store, native picker service, catalogue manager, status panel, and focused store/manager/widget tests. Modified the catalogue shell, dependency declarations, macOS DebugProfile/Release entitlements, README and phase plan. No files removed. Python scripts, canonical data and bundled YAML are unchanged.

The toolbar provides **Import YAML catalogue** and **Reset to bundled catalogue**. The status area identifies bundled versus saved local data, shows counts, and explains import/fallback errors with expandable technical details.

## Data and transaction behaviour

- The native macOS picker accepts `.yaml`/`.yml`; cancellation leaves the active catalogue and its browsing state intact.
- The limit is **5 MiB (5,242,880 bytes)**, approximately 6.7 times the current 778,911-byte snapshot. Length is checked before reading; streamed bytes are bounded again before UTF-8 decoding or YAML parsing, including if the file grows after selection. Invalid UTF-8 is rejected.
- The existing parser/repository validates the complete candidate, including GUID grouping and conflicting metadata. Both bundled and local input use that repository interface.
- Only validated content is saved. The macOS store flushes `active.yaml.pending` in the same directory, then renames it over `active.yaml` without deleting the old snapshot first. A failed staging write/rename keeps the prior active file. Incomplete `.pending` files are never read on startup.
- The in-memory catalogue changes only after save succeeds. While an operation is active, other catalogue operations are ignored/disabled and browsing interaction is paused. Success starts a fresh browsing/storage session so old selected-item indexes and stored scroll/expansion state are not applied to the replacement data. Failure/cancellation retains the existing session.
- Saved data lives under the directory returned by `getApplicationSupportDirectory()`, at `catalogue/active.yaml`. The original selected YAML and bundled asset are never modified. Imported origin is labelled generically as a saved local catalogue; original file names are not persisted.
- On launch, a valid saved import is used. With no saved import, bundled data is used and labelled as bundled. If saved data is invalid, oversized or unreadable, the app uses bundled data with a fallback notice/details. Invalid saved data is not silently overwritten; a valid import replaces it or Reset removes it.
- Reset validates the bundled candidate first, removes only the app's private saved import, then activates bundled data. If validation or removal fails, the current catalogue remains. Reset does not delete the source file chosen by David. Relaunch after a successful reset uses bundled data.
- If neither saved nor bundled data loads, Retry and Import remain available. No network fetch or Python execution occurs in the Flutter app.

## Native setup

Pinned dependencies added: `file_selector: 1.1.0`, `path_provider: 2.1.6`.

Official references: https://pub.dev/packages/file_selector and https://pub.dev/packages/path_provider.

macOS DebugProfile and Release configurations now declare `com.apple.security.files.user-selected.read-only` for the native file picker. App sandboxing stays enabled. Saving occurs in the app's own support directory; no write access to the selected source file is requested. macOS remains the implemented platform; other runners have not been generated or verified.

## Commands for David

From `flutter_app/`, in zsh:

```zsh
flutter pub get
flutter analyze
flutter test test/features/catalogue/catalogue_manager_test.dart test/data/file_catalogue_store_test.dart
flutter run -d macos
```

Retain the updated lockfile after dependency resolution. Fully stop and rebuild/relaunch for native plugin and entitlement changes. If Flutter cannot foreground the successful build:

```zsh
open build/macos/Build/Products/Debug/common_descent_listing.app
```

Existing data/episode/news tests remain relevant to broader acceptance in Phase 6; the commands above focus on this phase.

Tests added: import/save-before-activation, restart restoration, durable reset, cancellation, malformed and oversized input, failed save/reset, corrupt-saved fallback, overlapping-operation prevention, bounded streams, invalid UTF-8, ignored staging files, file-store replacement/failure, and toolbar-driven import/reset state changes.

Tests, dependency resolution, analysis, application runs and builds by the assistant: **None — manual verification requested.** Dart sources were formatted only. Native picker, sandbox access and real file-system behaviour remain subject to David's checks.

## Manual evidence

Record tester, date, macOS/Flutter versions, window/text scale, pass/fail, and notes/screenshots.

| Check | Expected result | Result |
| --- | --- | --- |
| Dependencies/analysis/tests | Complete successfully. | Pending |
| First launch | Bundled data loads if no private import exists; origin/counts are visible. | Pending |
| Picker cancellation | Same catalogue, search, selection and scroll session remain. | Pending |
| Valid import | Choose generated `data/segments.yaml`; validation succeeds, origin changes to saved local, and both catalogues use new data. | Pending |
| Changed dataset | Import a valid small fixture with different titles/counts; no stale episode/segment selection remains. | Pending |
| Malformed YAML/schema | Import fails with useful details; current catalogue and prior saved import remain. | Pending |
| Oversized/invalid encoding | Input is rejected and existing data remains active. | Pending |
| Relaunch offline | Saved import restores without the original source file being available and without network access. | Pending |
| Reset and relaunch | Bundled data returns and stays selected across relaunch; original selected file still exists. | Pending |
| Invalid saved snapshot | After deliberately corrupting only the app's private copy with the app stopped, relaunch uses bundled data with a notice. Restore using valid import or Reset. | Pending |
| File errors | Failed reads/writes/removal give an explanation without activating a partial candidate. Store tests cover deterministic failure; no need to alter system permissions. | Pending |
| Existing flows | Episode/news browsing, source links and separate summary/scroll storage still work. | Pending |
| Layout/accessibility | Status/errors, picker actions and reset remain usable on narrow/wide windows and with enlarged text/keyboard navigation. | Pending |

Outstanding risks: dependency/native integration, sandbox file access and UI behaviour are unverified until David runs the checks. Same-directory rename atomicity is intended for the current macOS target; other platforms need their own verification before release. File flushing plus rename avoids exposing partial writes, but no power-loss durability guarantee is claimed. Synchronous YAML parsing of allowed larger catalogues still needs responsiveness assessment during authorised acceptance work.

Suggested commit after review: `Add bounded YAML import with persistent catalogue and bundled reset`.

## Follow-up — selected-summary widget lifecycle assertion

David supplied a screenshot showing `_elements.contains(element)` failing inside the expanded selected-item original summary for episode 231. The screenshot does not include the full stack, so the precise framework trigger is not established.

The focused workaround replaces SelectableText inside both animated summary bodies with plain Text and a Copy summary action, and sets both summary tiles to maintain their content state across toggles. The distinct PageStorageKeys from the earlier scroll/expansion fix are retained. Created `news_summary_text.dart` and `news_summary_expansion_test.dart`; modified `episode_detail.dart`. No dataset or dependencies changed.

The new test uses synthetic summary text to exercise repeated mid-animation toggles, copying, and scrolling out/back. The existing storage test checks independent scroll and expansion restoration. Tests/analysis/app launch were not run by the assistant; source was formatted only.

From `flutter_app/`, in zsh:

```zsh
flutter analyze
flutter test test/features/episodes/news_summary_expansion_test.dart test/features/episodes/episode_detail_storage_test.dart
flutter run -d macos
```

Fully stop/relaunch, open episode 231 from its news item, repeatedly expand/collapse Selected item original summary, copy the text, scroll away/back, and also check Original news summary. If the assertion returns, retain the first terminal exception and full stack trace, since later framework assertions may be secondary errors. Verification remains pending; no additional implementation phase was started.

Suggested commit: `Stabilise expandable news summaries and add explicit copy action`.

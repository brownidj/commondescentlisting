# Episode sorting

## Goal and scope
Sort All and Side episodes by publication date, latest first or earliest first.
Sort Numbered episodes by title, A–Z or Z–A. Keep search and selection intact.

## Tasks and acceptance
- Carry optional UTC publication timestamps from the RSS exporter through segment
  YAML, parsing, grouping and Episode. Enrich saved catalogues from the existing
  episode metadata by GUID, without fetching or changing segment identities.
- Keep legacy imports valid: missing dates sort last in either direction.
- Remember each filter's order during the browser session. Default All and Side
  to latest first, Numbered to A–Z. Equal dates/titles retain source order.
- Provide an accessible order dropdown, including on narrow/enlarged layouts.
- Add sorting, date parsing/grouping and browser-control regression coverage.

## Done when / evidence
Implementation and tests written; format changed Dart files. David runs targeted
Flutter tests and analysis, then checks date reversal, alphabetical reversal,
filter switching, search and selection on macOS/iOS. Do not claim verification
until those checks run. No Git mutations or app launches.


## Implementation status — 3 November 2026
Implemented; manual verification pending. Enriched 1,630 segment records in each
saved catalogue for 391 GUIDs using existing published_raw metadata, preserving
record order, all existing fields and segment identities. The exporter now emits
UTC publication instants for future snapshots. Date grouping rejects conflicts;
legacy missing timestamps remain supported. No tests, analysis, builds or app
launches run. Dart formatting performed.

David: from flutter_app run the targeted tests and flutter analyze below, then
check both directions in each filter, with search text, selected detail and large
text/narrow windows. Record tester, environment, pass/fail and date when verified.

```zsh
flutter test test/features/episodes/episode_sorting_test.dart test/features/episodes/episode_browser_test.dart test/data/catalogue_parser_test.dart test/data/catalogue_repository_test.dart test/data/catalogue_offline_acceptance_test.dart
flutter analyze
```

Filter label refinement — 3 November 2026: use All, # and Side in a single
horizontal row, with horizontal scrolling only if narrow width or enlarged text
requires it. Preserve filtering/sorting and expose explanatory chip tooltips.
Update existing widget-test selectors; format Dart. Verification stays manual.

Listing refinement — 3 November 2026: shorten episode news counts to “n news
records” in list/detail views. Show a small document icon beside the navigation
chevron when the GUID has a bundled or activated local transcript, using the
existing availability facade and library-change notifier. Keep title width and
selection/search/sort behavior unchanged. Update existing widget coverage for
availability changes; formatting only, manual test execution.

News sorting — 3 November 2026
Goal/scope: add headline A–Z/Z–A sorting to the News browser like Numbered episodes.
Tasks/acceptance: controller owns case-insensitive trimmed headline comparison;
default A–Z; equal titles preserve source order and duplicate records; untitled
section entries sort by the displayed “News section” label. Dropdown below search
fits available width. Search, navigation and session order remain intact; source
catalogue is not mutated. Add focused controller/widget coverage and format Dart.
Done when code/tests supplied; David runs news_browser_test.dart and flutter
analyze, then verifies both directions, search and return navigation on macOS/iOS.
Record date, tester, environment and pass/fail. No automatic tests/app launches.

News listing rows — 3 November 2026: show headline, then “Episode n - Episode
 title - news starts at HH:MM:SS”, then “Item time unavailable” when no individual
item timestamp exists. Keep actual item timestamps when known; a section-only
record's start is never an item time. Side episodes keep the Side episode label;
missing section time says news start time unavailable. Remove per-tile review
notice while retaining underlying review data and existing detail context.
Update existing widget assertions, format Dart; manual test/layout verification.

## Episode title versus index search — 4 November 2026

Provide a Search in selector: Episode titles (default, preserving number search)
or Index. Index search matches names/aliases and reference fields across all index
categories and returns episodes with current valid indexed occurrences, excluding
rejected/deleted entries. Keep source transcripts unchanged; do not initiate
indexing/transcription/API requests. Show matching index names and coverage/loading/
retry/incomplete-result states. Empty queries retain the ordinary episode listing.

Reuse one lazy KnowledgeIndexController between Episodes and Indexes in the shell
so edits/deletions update both, preserve filter/order/detail behavior, avoid loading
transcripts for title-only browsing, and refresh on library/lifecycle changes.
Standalone browser accepts an injected index controller for isolated tests.
Acceptance: title and index choices behave differently; alias/category matches,
rejection/deletion/stale evidence exclusion, deduplicated episode results, filters,
sorting, updated edits, empty queries and narrow layout work. Existing focused
Flutter test/analyzer authorization applies. No paid requests, builds, launches,
Git actions or live registry changes during implementation.

Title/index search implemented with one lazy shared index controller and validated
occurrence-based episode results. Matching names and coverage/loading/retry states
are shown; edits/deletions propagate. All 29 affected tests passed, extended retry
coverage passed, and analyzer clean. Native acceptance pending; no API/media/Git
operations. See outputs/episode-index-search/README.md.

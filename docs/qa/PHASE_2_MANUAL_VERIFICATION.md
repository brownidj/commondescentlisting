# Phase 2 — Data Layer Verification

Status: implementation delivered; manual verification pending. Phase 3 is not started.

## Changes

Created immutable models in `flutter_app/lib/models/catalogue.dart`, the parser and repository in `flutter_app/lib/data/`, and two focused test files in `flutter_app/test/data/`. Modified the asset source, shell and `pubspec.yaml`. The shell now shows parsed episode/segment/news counts; record browsing remains deferred. Python and the canonical/bundled YAML are unchanged.

The direct YAML dependency is pinned to `yaml: 3.1.4`; dependency resolution and its generated lockfile are pending David's `flutter pub get`. Package usage reference: https://pub.dev/packages/yaml.

## Contract details

- Missing or explicit-null optional values stay null, including the review flag.
- Episode numbers are strings; finite numeric YAML scalars are normalised to strings. Fractional and letter-suffixed strings remain intact.
- Record positions are zero-based in `segments[index]` diagnostics and also reported as one-based record numbers for readers.
- Required GUID/title/type values must be non-empty strings. Unknown fields are ignored; unknown types remain generic segment data.
- An unversioned document is legacy v1; explicit `schema_version: 1` is accepted. Other declared versions are rejected.
- Times accept `MM:SS` (minutes may exceed 59) or `HH:MM:SS`. Seconds and the middle component of three-part times must be 0–59. Excessively large times are rejected before arithmetic conversion. An explicit zero time is retained as zero, not missing.
- Unsafe or malformed link strings remain source data but have no actionable `sourceUri`; no browser opening exists yet.
- Same-GUID records with contradictory episode title/number are rejected, with a source/record diagnostic. Different GUIDs are never merged by title.
- Lists are unmodifiable; duplicates and source order are retained. Session IDs use GUID plus source position and are not durable IDs.
- Repository loading is stateless: a full parsed/grouped catalogue is returned only after validation succeeds. Import activation/persistence remains Phase 5.

## Commands for David

From `flutter_app/`, in zsh:

```zsh
flutter pub get
flutter analyze
flutter test test/data/catalogue_parser_test.dart test/data/catalogue_repository_test.dart
flutter run -d macos
```

Tests created: parser and repository tests covering malformed YAML/schema/fields, nullable fields, unsafe URLs, timestamp ranges and meanings, fractional/suffixed numbers, GUID grouping, duplicates, immutable collections, conflicting metadata, and full bundled-snapshot coverage. The snapshot check compares counts to the file rather than fixed global totals and checks episode 255's known news/discussion times.

Tests/analysis/builds/app launches run by the assistant: **None — manual verification requested.** Source files were formatted with `dart format`; its unresolved-lints warnings reflect dependencies not yet fetched.

## Manual checklist

Record date, tester, OS, Flutter version, and Pass/Fail with notes.

- Dependency resolution and analysis complete successfully; retain the generated app lockfile for reproducible dependencies.
- Both focused test files pass.
- App loads offline once dependencies/build tools are available and reports counts matching the bundled snapshot (currently 391 episodes, 1,630 segments, 1,016 news records; these are not permanent limits).
- Episodes/News navigation still works and displays counts without claiming to provide browsing yet.
- Invalid data triggers the existing error/details/retry state; restore the canonical snapshot after any temporary edits.
- For an empty valid `segments: []` snapshot, the shell reports zero counts rather than a parse error.

Outstanding risks: tests and local app launch remain unverified; direct dependency is pinned but transitive lockfile generation is pending. Synchronous YAML parsing may need measurement with larger catalogues during authorised verification. macOS remains the provisional target.

Suggested commit message: `Add typed YAML catalogue parser and GUID-grouped repository`.

# Common Descent Listing — Flutter

The macOS shell provides responsive Episodes/News navigation, a bundled YAML snapshot, loading status, and error/retry handling. Phase 2 adds typed parsing, validation, GUID grouping and catalogue counts. Browsing individual records remains deferred.

## Setup

Open `flutter_app/` in an IDE with Dart and Flutter support and configure the installed Flutter SDK. From this directory, David should run:

```zsh
flutter pub get
flutter analyze
flutter run -d macos
```

The scaffold was generated with `flutter create --empty --no-pub --platforms=macos --project-name=common_descent_listing flutter_app`. No dependency resolution, analysis, tests, builds, or app launches were performed by the assistant. macOS is the provisional initial target from the plan; mobile runners have not been added. The development bundle identifier `com.example.commonDescentListing` must be replaced before distribution.

## Data snapshot

Canonical data: `../data/segments.yaml`. Bundled copy: `assets/data/segments.yaml`, declared in `pubspec.yaml`. Do not edit the bundled copy independently.

From the project root, copy an existing generated dataset into the asset:

```zsh
cp data/segments.yaml flutter_app/assets/data/segments.yaml
```

If a live refresh is wanted, first run the existing generator from the project root:

```zsh
.venv/bin/python main.py
```

The refresh downloads RSS and overwrites the Python export files. Copying an already-generated YAML needs no internet or refresh. Stop and relaunch the Flutter app after changing the asset. The app does not execute Python.

Follow `../docs/qa/PHASE_2_MANUAL_VERIFICATION.md` for the current acceptance checks. The earlier Phase 1 checklist remains as a historical shell checklist.

## Phase 2 data layer

The shell now validates and parses YAML through `CatalogueRepository` and shows episode, segment and news counts. Immutable models preserve source order, GUID grouping, unknown segment types, review flags, raw summaries and separate news-section/item timestamps. Episode/news browsing is not implemented yet.

The parser uses the pinned `yaml: 3.1.4` package. Run `flutter pub get` before analysis or tests; keep its generated lockfile. Follow `../docs/qa/PHASE_2_MANUAL_VERIFICATION.md` for the focused tests and manual checklist.

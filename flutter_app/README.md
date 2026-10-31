# Common Descent Listing — Flutter

The macOS app provides a searchable episode catalogue, responsive episode/segment details, a bundled offline YAML snapshot, and loading/error handling. Phase 2 provides typed parsing and GUID grouping; Phase 3 provides episode browsing. Separate news browsing remains planned for Phase 4.

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

Follow `../docs/qa/PHASE_3_MANUAL_VERIFICATION.md` for current acceptance checks. Earlier checklists remain as historical phase records.

## Phase 2 data layer

The app validates and parses YAML through `CatalogueRepository`. Immutable models preserve source order, GUID grouping, unknown segment types, review flags, raw summaries and separate news-section/item timestamps.

The parser uses the pinned `yaml: 3.1.4` package. Run `flutter pub get` before analysis or tests; keep its generated lockfile. Follow `../docs/qa/PHASE_2_MANUAL_VERIFICATION.md` for the focused tests and manual checklist.

## Phase 3 episode browsing

The Episodes destination now provides title/number search, All/Numbered/Side filters, GUID-based selection, and responsive list/detail navigation. Episode details preserve source segment order, show discussion parts and available times, explain inferred headline splits, and expose original news summaries. Valid episode links open in the system browser; invalid links have no action.

Run `flutter pub get` to resolve the newly pinned `url_launcher: 6.3.3` dependency and update the existing lockfile, then restart the app for native plugin registration. Follow `../docs/qa/PHASE_3_MANUAL_VERIFICATION.md` for commands and checks. A separate searchable News catalogue remains Phase 4.

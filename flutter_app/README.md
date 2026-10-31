# Common Descent Listing — Flutter

The macOS app provides searchable episode/news catalogues, responsive segment details, an offline bundled YAML snapshot, and local YAML import with persistence, fallback and reset. Phase 5 adds the local data-update workflow.

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

Follow `../docs/qa/PHASE_5_MANUAL_VERIFICATION.md` for current acceptance checks. Earlier checklists remain as historical phase records.

## Phase 2 data layer

The app validates and parses YAML through `CatalogueRepository`. Immutable models preserve source order, GUID grouping, unknown segment types, review flags, raw summaries and separate news-section/item timestamps.

The parser uses the pinned `yaml: 3.1.4` package. Run `flutter pub get` before analysis or tests; keep its generated lockfile. Follow `../docs/qa/PHASE_2_MANUAL_VERIFICATION.md` for the focused tests and manual checklist.

## Phase 3 episode browsing

The Episodes destination now provides title/number search, All/Numbered/Side filters, GUID-based selection, and responsive list/detail navigation. Episode details preserve source segment order, show discussion parts and available times, explain inferred headline splits, and expose original news summaries. Valid episode links open in the system browser; invalid links have no action.

Run `flutter pub get` to resolve the newly pinned `url_launcher: 6.3.3` dependency and update the existing lockfile, then restart the app for native plugin registration. Follow `../docs/qa/PHASE_3_MANUAL_VERIFICATION.md` for commands and checks. A separate searchable News catalogue remains Phase 4.

## Phase 4 news browsing

The News destination now lists every source news record with headline/episode context, review notices and available times. Search matches headline, episode title or number through the same matching policy used by Episodes. Duplicate headlines remain separate. Opening an item shows its episode, identifies and highlights the selected item, and exposes its original news summary. Back returns to the retained news search.

See `../docs/qa/PHASE_4_MANUAL_VERIFICATION.md` for current commands and checks. No dependencies were added in this phase. YAML replacement/persistence remains Phase 5.

## Phase 5 local catalogue updates

Use the toolbar's **Import YAML catalogue** action to choose a `.yaml`/`.yml` file up to 5 MiB. The complete file must validate and save before it replaces the active catalogue. Failed/cancelled imports retain current data. **Reset to bundled catalogue** removes only the app's saved copy; your selected source file is not changed or deleted.

The last valid import is kept in the app support directory at `catalogue/active.yaml`, loaded on future launches, and labelled as saved local data. Missing local data uses bundled data; corrupt/unreadable saved data triggers a bundled fallback notice. Import/reset success resets catalogue browsing state; failures preserve it. No network refresh happens inside Flutter.

Run `flutter pub get`, retain the updated lockfile, and fully restart/rebuild for the file-picker/storage plugins and macOS read-only user-selected-file entitlement. See `../docs/qa/PHASE_5_MANUAL_VERIFICATION.md` for commands, the transaction contract, and manual checks. Phase 6 acceptance remains separate.

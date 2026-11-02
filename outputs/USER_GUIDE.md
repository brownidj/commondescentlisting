# Common Descent Listing — Operating Guide

The macOS app browses episodes and news from a local YAML catalogue. It works from bundled or previously imported data; it does not run Python, stream audio or refresh RSS itself.

## Open the project and run

Open `flutter_app/` in an IDE with Flutter/Dart support. Terminal commands below use zsh.

```zsh
cd '/Users/david/Library/Mobile Documents/com~apple~CloudDocs/PyCharm projects/CommonDescentListing/flutter_app'
flutter pub get
flutter run -d macos
```

If a successful build does not foreground the window, open the build explicitly. For the Phase 6 release build:

```zsh
open build/macos/Build/Products/Release/common_descent_listing.app
```

For a debug build, replace `Release` with `Debug`. Do not launch multiple copies intentionally while testing persisted catalogue changes. A full restart is required after native plugin/entitlement changes; hot reload is insufficient.

## Browse episodes and news

- **Episodes:** search by title/number, choose All/Numbered/Side episodes, then select an episode. Results retain source order.
- **News:** search a headline, episode title or number. Repeated headlines are separate source records. Selecting one opens its episode and identifies that item.
- Narrow windows show a detail pane with Back; wider windows show episode list/detail together. Returning to news preserves its query.
- Expand original summaries for context and use **Copy summary** to copy the text.
- “News section starts at” refers to the whole section. Unknown item times are unavailable, not zero. Separate discussion parts have their own labels/times.
- **Open episode page** launches the published page in your default browser. This action needs network access to load the website; catalogue browsing does not.

## Generate updated YAML

From the project root, using zsh:

```zsh
cd '/Users/david/Library/Mobile Documents/com~apple~CloudDocs/PyCharm projects/CommonDescentListing'
.venv/bin/python main.py
```

This downloads the current RSS metadata and overwrites `data/segments.yaml` and `data/segments.rss.xml`. It does not download audio. To regenerate from an already saved RSS snapshot instead:

```zsh
.venv/bin/python main.py --input data/segments.rss.xml --output data/segments-review.yaml
```

The review command writes separate YAML/RSS review files. Keep manually reviewed material separately before refreshing generated files.

## Import without rebuilding

1. Choose **Import YAML catalogue** in the app toolbar (document/open icon).
2. Select the generated `.yaml` or `.yml` file, up to **5 MiB**.
3. Wait for validation and saving. The status changes to **Saved local catalogue** with its counts.
4. The app will use its private saved copy on future launches, even if the selected original moves.

Cancelling, invalid YAML/encoding, oversized input or a save failure retains the previous active catalogue. Technical details explain errors. Successful import starts a fresh browsing session; it does not merge datasets.

**Reset to bundled catalogue** (restore icon) removes only the app-private import, returns to bundled data and persists that choice across relaunch. It does not delete your original YAML file. Corrupt/unreadable saved data falls back to the bundled snapshot with a notice.

The current macOS private copy is under the app support directory at:

```text
~/Library/Containers/com.example.commonDescentListing/Data/Library/Application Support/com.example.commonDescentListing/catalogue/active.yaml
```

Normal updates/reset should use the app rather than editing this private file.

## Update the bundled fallback deliberately

Canonical YAML is `data/segments.yaml`; Flutter's bundled snapshot is a copy. From the project root:

```zsh
cp data/segments.yaml flutter_app/assets/data/segments.yaml
```

Then rebuild/relaunch. Do not edit the two copies independently. An existing saved import still takes precedence until Reset is selected.

## Repeat acceptance checks

From `flutter_app/`:

```zsh
flutter analyze
flutter test
flutter build macos --release
```

Phase 6 results and native checks are in `docs/qa/PHASE_6_ACCEPTANCE_REPORT.md` relative to the project root. For failures, retain the first exception, full stack and reproduction steps.

## Limits

This is the loaded feed catalogue, not an independently verified complete archive. Automatic headline boundaries may need review; original summaries are retained. The app has no playback, accounts, cloud sync or persistent bookmarks. Only macOS has been built/tested; distribution and other platforms are separate work.

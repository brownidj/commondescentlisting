# Common Descent Listing — Flutter

macOS episode/news catalogue using local Option 2 YAML. Includes shared search, episode filters, segment details, original-summary copying, external source links, bounded YAML import, saved-catalogue restoration, fallback and reset.

See [operating guide](../docs/USER_GUIDE.md) for specific zsh instructions, data updates and recovery. The [Phase 6 acceptance report](../docs/qa/PHASE_6_ACCEPTANCE_REPORT.md) records the final test/build/native results and limitations.

From this directory, using zsh:

```zsh
flutter pub get
flutter run -d macos
```

For verification:

```zsh
flutter analyze
flutter test
flutter build macos --release
```

Canonical data is `../data/segments.yaml`. The bundled asset is `assets/data/segments.yaml`; imported catalogues are separate private copies. The app never executes the retained Python generator. The current import limit is 5 MiB.

The macOS runner uses a development `com.example.commonDescentListing` identifier. Replace it and perform distribution/signing work before release to other users. Other platform runners have not been added or tested. Follow [programming criteria](../docs/PROGRAMMING_CRITERIA.md) before generating any code.

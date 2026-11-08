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

The macOS runner uses a development `com.example.commonDescentListing` identifier. Replace it and perform distribution/signing work before release to other users. The iOS device runner is described below; Android/web runners are not implemented. Follow [programming criteria](../docs/PROGRAMMING_CRITERIA.md) before generating any code.

## iOS device version

For repeated use, install **CD List** with `zsh ../scripts/run_ios_release.zsh` from this directory, then open it from the phone's Home Screen on later occasions. This verified launcher uses direct Xcode builds outside iCloud Drive to avoid this Mac's Flutter status-255 build failure. The Flutter Terminal session is not needed for subsequent launches. See the [current run guide](../docs/RUNNING_THE_APP.md#install-on-the-iphone-for-repeated-use) for zsh commands, logs and central-library requirements.

An iOS release runner has also been built, installed and launched on David's iPhone 13 Pro Max (`00008110-001E48A02187601E`). See [device deployment notes](../docs/IOS_DEVICE_RUN.md) for signing details, verification limits, and zsh build/launch commands. This supplements the macOS acceptance report; it does not claim full iOS UI acceptance.

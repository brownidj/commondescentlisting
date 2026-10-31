# Phase 1 — Manual Verification

Status: implementation delivered; verification pending David's local checks.

Record date, tester, macOS version, Flutter version, and window configuration when checking. Mark each item Pass/Fail and attach relevant notes/screenshots. Commands below were not run by the assistant.

From `flutter_app/`:

```zsh
flutter pub get
flutter analyze
flutter run -d macos
```

| Check | Expected result | Result |
| --- | --- | --- |
| IDE opens project | Dart/Flutter sources and macOS target available. | Pending |
| Dependencies and analysis | Commands complete without errors. | Pending |
| Launch | Window opens with Common Descent Listing title. | Pending |
| Asset load | Loading resolves to a message confirming bundled YAML was read, without claiming schema validation. | Pending |
| Offline launch | Once dependencies/build tools are available, relaunch without networking; the asset still loads. | Pending |
| Navigation | Episodes/News switch heading, icon, and placeholder text. | Pending |
| Responsive layout | Resize across 720 logical pixels; rail switches to bottom navigation without overflow or loss of selection. | Pending |
| Accessibility | Keyboard focus works and enlarged text remains readable; content scrolls when needed. | Pending |
| Empty-data error | Temporarily empty only the bundled YAML and relaunch; error, Retry and expandable details appear. Restore the asset afterward and relaunch. | Pending |
| Python unaffected | Canonical data and generator are unchanged by the Flutter app. | Pending |

Restore the bundled asset from the project root after error checks:

```zsh
cp data/segments.yaml flutter_app/assets/data/segments.yaml
```

Loading may be brief. Retry reads the same bundle; it does not fetch or import data. Episode and news records are not displayed in this phase.

Tests created/modified: none. Tests, analysis, dependency resolution, app launches, and builds run by the assistant: none — manual verification requested.

Outstanding: local verification and confirmation of macOS as the initial target. Replace the development bundle identifier before distribution.

Suggested commit message after review: `Add Phase 1 macOS Flutter shell and bundled YAML asset`.

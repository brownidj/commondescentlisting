# Phase 6 — Acceptance Review and Handover

Date: 31 October 2026 (Australia/Brisbane).
Tester: Codex, with David's explicit authorisation to run analysis, tests, builds and the application.

**Status: implementation and macOS technical acceptance completed. David's product sign-off remains pending.** This is acceptance of the implemented macOS scope, not publishing approval or certification for other platforms.

## Environment

- macOS 27.0.1, build 26A434, Apple Silicon.
- Flutter 3.47.1 stable, framework revision 6655482ec0.
- Dart 3.13.1.
- Release build: `flutter_app/build/macos/Build/Products/Release/common_descent_listing.app`, reported by Flutter as 44.4 MB.
- Native checks used the release application, macOS file picker, accessibility observations and visual inspection. Automated tests used Flutter's test environment.

See [environment evidence](evidence/phase6/environment.txt).

## Results

| Requirement/check | Result | Evidence and limits |
| --- | --- | --- |
| Static analysis | PASS | Final `flutter analyze`: no issues found. [Log](evidence/phase6/analyze.txt). |
| Complete automated suite | PASS | Final `flutter test --reporter expanded`: all 35 tests passed. [Log](evidence/phase6/tests.txt). |
| macOS release build | PASS with toolchain notices | Built successfully. Xcode/Flutter printed architecture and device-placeholder notices; no global Flutter settings were changed. [Log](evidence/phase6/build-release.txt). |
| Actual catalogue preservation | PASS | Tests compare source record/GUID coverage and order; current snapshot has 391 episodes, 1,630 segments and 1,016 news records. Native startup displayed matching episode/news counts. Canonical and bundled YAML also compare byte-for-byte. |
| Offline data path | PASS, bounded claim | Actual bundled asset loaded with Dart HTTP client creation disabled; no network client was needed. The device's network connection was not disabled, so this is not a whole-device disconnected-network test. |
| Load/search responsiveness | PASS for current data | Final suite measured asset load/parse/group at 127.4 ms and 100 news searches at 20.1 ms. Standalone measurement was 118.5 ms/18.1 ms. These are test/debug measurements, not release performance guarantees. [Standalone log](evidence/phase6/offline-performance.txt). |
| Episode title/number search | PASS | Automated matching checks and native search for ` 37.5 ` returned More Birds, episode 37.5. |
| Keyboard operation | PASS for sampled flow | Native Tab from the search field, then Return, activated Clear and restored the 391-entry list. This is not a complete screen-reader audit. |
| Numbered/side filters and empty states | PASS, automated | Existing widget/controller tests cover filters, no-match and empty catalogue states. |
| News duplicates and exact selection | PASS | Automated tests preserve same-title records within/across episodes. Native fixture import displayed two separate repeated headlines. Episode 231 item 4 opened the correct episode and selection banner. |
| Summary rendering and copying | PASS | Summary toggle/scroll/copy regression and storage restoration tests pass. Native episode 231 selected original summary expanded normally with raw text and Copy summary. |
| News versus item times | PASS | Native episode 255 showed unknown headline time and `News section starts at 00:05:25`; discussion Part 1/2 remained separate at `00:47:35`/`01:16:05`. Automated assertions cover the same distinction and explicit zero times. |
| External source page | PASS, native | Open episode page launched Safari at `https://commondescentpodcast.podbean.com/e/episode-255-plant-origins/`. The test-created browser window was closed afterward. |
| Native picker/cancellation | PASS | File picker opened normally; cancelling preserved the news search and its four episode-231 results. |
| Native valid import | PASS | Synthetic fixture imported successfully: saved local origin, one episode, two distinct repeated news records. |
| Native invalid/oversized import | PASS | Malformed YAML and a 5,242,881-byte file were rejected; the prior one-episode/two-news catalogue remained active. Unit tests additionally check invalid encoding and write failures. |
| Saved import relaunch | PASS, native | After quitting and relaunching, the fixture was restored from private storage without selecting its source again. |
| Corrupt-saved fallback | PASS, native | Only the synthetic app-private snapshot was deliberately corrupted while the app was stopped. Relaunch loaded 391 bundled episodes and showed the fallback notice; technical details displayed the YAML error. |
| Reset/relaunch | PASS, native | Reset removed the test import, restored bundled data, and a fresh relaunch kept bundled data without a fallback warning. Original user data/source assets were not changed. |
| Safe persistence/failure recovery | PASS, automated and sampled native | Tests cover save-before-activation, failed staging writes, ignored pending files, failed reset and serialised operations. Native import/restart/reset flows also passed. This is not a hardware power-loss test. |
| Narrow/wide layout | PASS | Native window zoom switched from a single detail pane to list/detail while retaining episode 255, then back to the original size. Widget tests also cover resize. |
| Enlarged text | PASS, automated | 400×600 logical pixels with 2× text scale remains scrollable and supports episode selection. Corrected a test tap-position issue found during this phase. |
| Data provenance/copy | PASS for reviewed views | UI says loaded catalogue/source order, exposes raw summaries and review notices, and does not promise a proven complete archive or editorially verified headlines. |
| Operating instructions | PASS | [User guide](USER_GUIDE.md) covers setup, start, data generation, asset updates, import/reset, recovery and limitations, with zsh command examples. |

## Defects found and corrected

1. **Enlarged-text test tapped below the viewport.** The test discovered a cached row but attempted to tap its offscreen centre. Centring it with `Scrollable.ensureVisible(..., alignment: 0.5)` before tapping fixed the test. No application behaviour was changed for this issue.
2. **Technical error details showed a blank panel in the release app.** These animated expansion bodies still used SelectableText, matching the problematic pattern previously removed from news summaries. Changed both status and startup error bodies to plain Text and retained their state across toggles. Added two repeated-expansion regression cases. The final release's corrupt-saved error details rendered visibly; the initial failure's precise framework trigger is not claimed to be proven.
3. **Single-episode count grammar.** Status and episode-list count labels now use singular “episode” for a one-episode catalogue.

No unresolved critical defect was observed in the tested scope.

## Files changed for Phase 6

Created:

- `flutter_app/test/data/catalogue_offline_acceptance_test.dart`.
- This report, `docs/USER_GUIDE.md`, and `docs/qa/evidence/phase6/` logs/notes.

Modified:

- `flutter_app/lib/features/catalogue/catalogue_shell.dart`: stable plain-text startup error details.
- `flutter_app/lib/features/catalogue/catalogue_status.dart`: stable plain-text error details and singular count copy.
- `flutter_app/lib/features/episodes/episode_browser.dart`: singular count copy.
- `flutter_app/test/features/catalogue/catalogue_manager_test.dart`: error-details regression cases.
- `flutter_app/test/features/episodes/episode_browser_test.dart`: visible-target correction for enlarged-text test.
- Root/app README files and the implementation plan.

Removed: none. Python generator, YAML schema and datasets: unchanged. No commits, branches, tags or pushes were performed.

## Authorised commands actually run

From `flutter_app/`, using zsh:

```zsh
flutter analyze
flutter test --reporter expanded
flutter test test/features/episodes/episode_browser_test.dart
flutter test test/data/catalogue_offline_acceptance_test.dart --reporter expanded
flutter build macos --release
```

Sources were also formatted with `dart format`. Initial failures were addressed and affected checks rerun; the evidence files contain final successful results. The release application was launched and operated through native computer-use tools. It remains open on the original bundled-data baseline. [Restoration note](evidence/phase6/restored-state.txt).

## Specific handover instructions

1. Read `docs/USER_GUIDE.md` for the current operating workflow.
2. Use the open release app to review episode/news presentation and the Copy summary interaction.
3. Import your generated YAML through the toolbar for updates without rebuilding. Asset copying is only needed when deliberately changing the bundled fallback.
4. Review these changes and the final logs before committing.
5. If a problem remains, send the first terminal error with the full stack and the steps/episode/item involved; later assertions can be secondary failures.

Suggested commit: `Complete macOS acceptance checks and stabilise technical error details`.

## Remaining limitations and user sign-off

- Full VoiceOver/screen-reader coverage and exhaustive keyboard/contrast checks are not certified. Only the stated keyboard, accessibility observations and enlarged-text/layout checks were performed.
- System networking was left unchanged; the offline check blocked Dart HTTP in the automated asset-loading path.
- Large-file responsiveness up to the full 5 MiB limit is not benchmarked. No claim of constant-time parsing or power-loss durability is made.
- Only macOS was built and exercised. Mobile/web runners, store packaging, signing/notarisation and publication remain separate tasks. The development bundle identifier still needs replacement before distribution.
- Headline splits still require review, absent timestamps remain unknown, and the feed's archive completeness is not independently established.
- David's final product acceptance is not implied by technical test results. No further phase or publishing action was started.

# iOS Device Build and Launch

## Install CD List for repeated use — 9 November 2026

Use the release version for an app that you can reopen from the phone's Home
Screen without a Flutter/debugger session. Unlock David's paired iPhone, then run
these commands in zsh:

```zsh
cd '/Users/david/Library/Mobile Documents/com~apple~CloudDocs/PyCharm projects/CD List'
export PATH="/Users/david/development/flutter/bin:$PATH"
zsh scripts/run_ios_release.zsh
```

This is the preferred route on this Mac. The ordinary `flutter run --release`
route has returned an opaque Xcode status 255. The launcher generates current
Flutter release configuration with `--config-only`, then builds with Xcode using
`~/Library/Developer/Xcode/DerivedData/CD List-release` outside iCloud Drive. It
installs in place and launches with `devicectl`; the default device is David's
`00008110-001E48A02187601E`. From `flutter_app/`, run
`zsh ../scripts/run_ios_release.zsh` instead. An optional first argument selects
another paired device UDID.

Verified on 9 November 2026: configuration, signed Release build, installation
and launch all succeeded through this launcher. The compiled display name is
CD List. Logs are in `outputs/ios-release/2026-11-09_07-40-46-h4waEM/`.

After installation, tap **CD List**
on the Home Screen for subsequent launches, including after restarting the phone.
Terminal and a Mac connection are not required for later ordinary launches.
Repeat the command to install a new version, not each time you want to use it.
Keep the existing bundle identifier and update in place rather than uninstalling
to retain saved app data. Development signing may need renewal later; reinstall
an updated signed build if iOS requires it.

The installed update uses the CD List display name and the ammonite/headphones
icon. Installation/launch were verified through device tooling; Home Screen
appearance and reopening after a phone restart still need manual confirmation.
If installation succeeds but automatic launch is refused because the phone is
locked, unlock it and tap the icon manually.

Server-hosted audio/transcripts/indexes still need the central library server
running and reachable on the network. Transcription/preparation runs on the Mac.
See [RUNNING_THE_APP.md](RUNNING_THE_APP.md) for server setup. For an opaque Xcode
status 255 or iCloud signing metadata failure, use the direct Xcode workflow below
with DerivedData outside iCloud Drive, followed by the install and launch commands.

Manual check: after installation, close the app and reopen it from its Home Screen
icon; also check after restarting the phone. Confirm the CD List label, proper
icon and retained saved data. These Home Screen/restart checks remain manual;
the verified build/install/launch results above are separate.

### Launcher logs and configuration

Run logs are under `outputs/ios-release/<run>/`: `configuration.log`, `build.log`,
`install.log`/`install.json`, `launch.log`/`launch.json`, and `result.txt`. Failures
stop at their stage and print a log path. Installation and launch are reported
separately, including successful installation followed by a locked-phone denial.

Set `CD_LIST_FLUTTER` to a specific Flutter executable if it is not on PATH.
`CD_LIST_IOS_DERIVED_DATA` can select another local Xcode cache outside the
project/iCloud. Run one deployment at a time. Do not uninstall the app, delete
personal files or clear global Xcode caches to work around this error.

## Icon update — 8 November 2026

The existing proper ammonite/headphones AppIcon assets were rebuilt and installed
over the existing app on David's iPhone 13 Pro Max. Bundle ID remains
org.topository.commondescentlisting; version remains 0.1.0+1. Installation succeeded
without uninstalling or clearing app data. The compiled primary icon was inspected
and contains the correct artwork. Launch was denied because the phone was locked;
unlock it and open the app, then confirm the Home Screen icon visually.

For this update, Flutter's wrapper reported Xcode status 255. A direct native
build inside the iCloud project failed codesigning due to FinderInfo metadata on
Flutter.framework. Building with local DerivedData outside iCloud succeeded:

```zsh
cd '/Users/david/Library/Mobile Documents/com~apple~CloudDocs/PyCharm projects/CD List/flutter_app'
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Release -destination 'id=00008110-001E48A02187601E' -allowProvisioningUpdates -allowProvisioningDeviceRegistration -derivedDataPath '/Users/david/Library/Developer/Xcode/DerivedData/CD List-icon' build
```

Build logs and compiled icon evidence are under outputs/app-icon/ in the project;
see IOS_UPDATE_2026-11-08.md there. This is deployment/icon verification, not a
full iOS UI acceptance run. No tests/analysis, source changes or Git operations.

## Original deployment — 31 October 2026

Date: 31 October 2026. Authorised by David's request to create and run a version for the device below.

## Deployment result

- Device: David, iPhone 13 Pro Max, connected wirelessly.
- UDID: `00008110-001E48A02187601E`.
- OS: iOS 27.0.1 (24A446).
- App: Common Descent Listing, version `0.1.0+1`, Release.
- Bundle identifier: `org.topository.commondescentlisting`.
- Development team: `QL5QBFGDB7`, matching the existing Sudoku project team.
- Xcode release build: **BUILD SUCCEEDED**.
- Installation: **succeeded** through `devicectl`.
- Launch: **succeeded** through `devicectl`.
- Follow-up process query: app executable running as PID 24209 at the deployed Runner.app path. PID is session-specific.

The app is left running on the phone. Its on-device visual presentation and native picker interactions have not been inspected through remote UI control; this result establishes signed build, installation and running process, not a full iOS acceptance audit.

## Project changes

- Added the generated iOS runner under `flutter_app/ios/` and its Flutter project metadata.
- Configured the development team and unique app bundle identifier in the iOS Xcode project.
- Added `public.yaml` to the shared YAML picker type group, since iOS uses uniform type identifiers rather than extension-only filtering. References: [file_selector documentation](https://pub.dev/packages/file_selector), [Apple YAML type](https://developer.apple.com/documentation/uniformtypeidentifiers/uttype-swift.struct/yaml).
- Removed the unused generated counter-app test introduced by scaffolding; the actual existing test suite remains intact.
- Python code and datasets are unchanged.

## Verification

`flutter analyze`: no issues found.

`flutter test --reporter expanded`: all 35 tests passed.

The initial Flutter deployment had no development certificate available. Adding the existing developer team and running Xcode automatic provisioning produced a signed release build. A Flutter wrapper attempt returned status 255; the explicit native Xcode build succeeded. Deployment then used the built app from Xcode DerivedData. No Git mutations were performed.

## Zsh instructions for another run

Historical Flutter entry point, from this project (the launcher above is now
preferred because this route has returned status 255 on this Mac):

```zsh
cd '/Users/david/Library/Mobile Documents/com~apple~CloudDocs/PyCharm projects/CD List/flutter_app'
flutter run --release -d 00008110-001E48A02187601E
```

If Flutter again reports an opaque Xcode failure, open the workspace and run Runner on the paired device in Xcode, or use this explicit native build/install/launch workflow after Flutter configuration has been generated:

```zsh
cd '/Users/david/Library/Mobile Documents/com~apple~CloudDocs/PyCharm projects/CD List/flutter_app'
ios_derived_data="${TMPDIR%/}/common-descent-ios-device"
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Release -destination 'id=00008110-001E48A02187601E' -allowProvisioningUpdates -allowProvisioningDeviceRegistration -derivedDataPath "$ios_derived_data" build
xcrun devicectl device install app --device 00008110-001E48A02187601E "$ios_derived_data/Build/Products/Release-iphoneos/Runner.app"
xcrun devicectl device process launch --device 00008110-001E48A02187601E org.topository.commondescentlisting
```

The current deployment used Xcode's default DerivedData directory rather than the explicit temporary directory shown for repeatability above. Device pairing, an available signing account/profile, and an unlocked device may be needed on later runs.

## Device review checklist

On the phone, check episode/news browsing, keyboard/text-size layouts, original-summary copying, source links, and importing a generated YAML through Files. Verify relaunch restores the imported catalogue and Reset returns to bundled data. These device-specific UI checks remain for review.

Suggested commit: `Add signed iOS runner and YAML picker support for device deployment`.

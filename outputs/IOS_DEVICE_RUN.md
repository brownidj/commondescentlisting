# iOS Device Build and Launch

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

Standard Flutter entry point, from this project:

```zsh
cd '/Users/david/Library/Mobile Documents/com~apple~CloudDocs/PyCharm projects/CommonDescentListing/flutter_app'
flutter run --release -d 00008110-001E48A02187601E
```

If Flutter again reports an opaque Xcode failure, open the workspace and run Runner on the paired device in Xcode, or use this explicit native build/install/launch workflow after Flutter configuration has been generated:

```zsh
cd '/Users/david/Library/Mobile Documents/com~apple~CloudDocs/PyCharm projects/CommonDescentListing/flutter_app'
ios_derived_data="${TMPDIR%/}/common-descent-ios-device"
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Release -destination 'id=00008110-001E48A02187601E' -allowProvisioningUpdates -allowProvisioningDeviceRegistration -derivedDataPath "$ios_derived_data" build
xcrun devicectl device install app --device 00008110-001E48A02187601E "$ios_derived_data/Build/Products/Release-iphoneos/Runner.app"
xcrun devicectl device process launch --device 00008110-001E48A02187601E org.topository.commondescentlisting
```

The current deployment used Xcode's default DerivedData directory rather than the explicit temporary directory shown for repeatability above. Device pairing, an available signing account/profile, and an unlocked device may be needed on later runs.

## Device review checklist

On the phone, check episode/news browsing, keyboard/text-size layouts, original-summary copying, source links, and importing a generated YAML through Files. Verify relaunch restores the imported catalogue and Reset returns to bundled data. These device-specific UI checks remain for review.

Suggested commit: `Add signed iOS runner and YAML picker support for device deployment`.

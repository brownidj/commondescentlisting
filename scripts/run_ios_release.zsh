#!/bin/zsh
# Install a standalone release using a local Xcode cache outside iCloud Drive.
set -euo pipefail
umask 077

if (( $# > 1 )); then
  print -u2 'Usage: scripts/run_ios_release.zsh [DEVICE_UDID]'
  exit 2
fi
if [[ "${1:-}" == '--help' || "${1:-}" == '-h' ]]; then
  print 'Usage: scripts/run_ios_release.zsh [DEVICE_UDID]'
  print 'Build, update and launch CD List Release on the paired iPhone.'
  print 'Default device: 00008110-001E48A02187601E'
  print 'Unlock the phone first. Later launches use its Home Screen icon.'
  print 'Overrides: CD_LIST_FLUTTER (Flutter executable), CD_LIST_IOS_DERIVED_DATA (local Xcode cache).'
  exit 0
fi

ios_project="${0:A:h:h}"
ios_device="${1:-00008110-001E48A02187601E}"
ios_flutter="${CD_LIST_FLUTTER:-flutter}"
ios_derived="${CD_LIST_IOS_DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/CD List-release}"
ios_derived="${ios_derived:A}"
if [[ ! "$ios_device" =~ '^[A-Za-z0-9-]+$' ]]; then
  print -u2 'Supply the paired device UDID, with no spaces or destination options.'
  exit 2
fi
if [[ "$ios_derived" == "$ios_project" || "$ios_derived" == "$ios_project"/* ||
      "$ios_derived" == *'/Library/Mobile Documents/'* ]]; then
  print -u2 'Use a local Xcode cache outside the project and iCloud Drive.'
  exit 2
fi
if ! command -v "$ios_flutter" >/dev/null 2>&1; then
  print -u2 'Flutter not found. Add the Flutter SDK bin directory to PATH, or set CD_LIST_FLUTTER to its executable.'
  exit 2
fi
for ios_tool in xcodebuild xcrun; do
  if ! command -v "$ios_tool" >/dev/null 2>&1; then
    print -u2 "Missing $ios_tool. Configure Xcode before running this script."
    exit 2
  fi
done

mkdir -p "$ios_project/outputs/ios-release"
ios_run_time="$(TZ=Australia/Brisbane date '+%Y-%m-%d_%H-%M-%S')"
ios_logs="$(mktemp -d "$ios_project/outputs/ios-release/${ios_run_time}-XXXXXX")"
print -- "Release deployment logs: $ios_logs"
print -- 'Unlock the phone. Keep this Terminal open until installation finishes.'
cd "$ios_project/flutter_app"

ios_stage() {
  local ios_phase="$1"
  shift
  local ios_log="$ios_logs/$ios_phase.log"
  print -- "$ios_phase…"
  if "$@" > "$ios_log" 2>&1; then
    return 0
  else
    local ios_result=$?
    print -u2 -- "$ios_phase failed (exit $ios_result). Full log: $ios_log"
    tail -n 35 "$ios_log" >&2
    return "$ios_result"
  fi
}

# Generate current release configuration/plugins without Flutter's build wrapper.
ios_stage configuration "$ios_flutter" build ios --release --config-only
ios_stage build xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner \
  -configuration Release -destination "id=$ios_device" \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  -derivedDataPath "$ios_derived" build

ios_app="$ios_derived/Build/Products/Release-iphoneos/Runner.app"
if [[ ! -f "$ios_app/Info.plist" ]]; then
  print -u2 -- "The successful build did not produce the expected app: $ios_app"
  exit 1
fi
ios_bundle="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$ios_app/Info.plist")"
ios_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$ios_app/Info.plist")"
if [[ "$ios_bundle" != 'org.topository.commondescentlisting' ]]; then
  print -u2 -- "Unexpected bundle identifier: $ios_bundle. Installation stopped."
  exit 1
fi
ios_stage install xcrun devicectl device install app --timeout 180 \
  --device "$ios_device" --json-output "$ios_logs/install.json" "$ios_app"
print -- "Installed $ios_name. The existing app was updated without uninstalling."

print -- 'launch…'
if xcrun devicectl device process launch --timeout 60 --device "$ios_device" \
    --json-output "$ios_logs/launch.json" "$ios_bundle" > "$ios_logs/launch.log" 2>&1; then
  print -- "Launched $ios_name. Open it from the Home Screen on subsequent occasions."
  print -r -- "Installed and launched: $ios_name ($ios_bundle)" > "$ios_logs/result.txt"
else
  ios_launch_result=$?
  ios_launch_message="$(<"$ios_logs/launch.log")"
  if [[ "$ios_launch_message" == *'BSErrorCodeDescription = Locked'* ]]; then
    print -- "Installation succeeded, but the phone is locked. Unlock it and tap $ios_name."
    print -r -- "Installed; launch pending phone unlock: $ios_name ($ios_bundle)" > "$ios_logs/result.txt"
  else
    print -u2 -- "Installation succeeded, but launch failed (exit $ios_launch_result). Full log: $ios_logs/launch.log"
    tail -n 25 "$ios_logs/launch.log" >&2
    print -r -- "Installed; launch failed: $ios_name ($ios_bundle)" > "$ios_logs/result.txt"
    exit "$ios_launch_result"
  fi
fi
print -- 'No Flutter Terminal session is required for later Home Screen launches.'

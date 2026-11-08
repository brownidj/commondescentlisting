# Common Descent Listing application icon — 7 November 2026

## Project directory name — 9 November 2026

Goal: rename the project and its associated named directories to CD List.
This request extends the earlier display-name-only scope below. Rename the
project root, PyCharm module, icon export and named Xcode caches; update current
instructions, project-folder prompts and local environment paths. Preserve the
Dart package identifier (spaces are invalid), bundle identifiers, saved data,
generic structural folders and historical evidence. No Git operations.

Acceptance: the project resides in `PyCharm projects/CD List`, PyCharm references
the renamed module/interpreter, and current commands use the new quoted path.
Existing Python environments and generated Flutter configuration must point at
the moved project. Do not run builds, tests, analysis or the app for this rename.
Record changed files, limitations and manual verification in
`outputs/project-rename/README.md`. Implementation and runtime verification are
separate; reopen the moved project in PyCharm before using its run configurations.

Implemented: project root and associated names/paths moved to CD List. Updated
PyCharm module, SDK/recent-project references, environment launchers, one local
dependency path, generated Flutter configuration, current docs and project-folder
prompt. File/path inspection only; no tests, analysis, builds, app launches or
Git commands. Runtime acceptance remains manual. See outputs/project-rename/.

## Repeatable iPhone release deployment — 9 November 2026

Goal: resolve the reported opaque Xcode status 255 during phone deployment and
provide one repeatable zsh command. Scope: configure Flutter release without its
build wrapper, direct Xcode build with DerivedData outside iCloud, in-place
installation and independent launch reporting. Retain bundle ID/data, existing
signing and artwork. Save stage logs in project outputs, stop on stage failure,
and distinguish installation success from a locked-phone launch denial.

Implemented scripts/run_ios_release.zsh and updated current run/iOS/Flutter/script
documentation. Shell syntax passed. Launcher configuration, signed build,
installation and launch succeeded on 00008110-001E48A02187601E; compiled name
CD List. Evidence: outputs/ios-release/2026-11-09_07-40-46-h4waEM/. No app source
fix was required by the direct build. The wrapper's generic 255 does not establish
its exact root cause; the previous iCloud FinderInfo failure is separately
documented. No claim that global Flutter/Xcode issues have been repaired.

No new unit tests for the deployment wrapper; no Flutter tests or analysis run.
Home Screen appearance/reopening after restart remain manual. No uninstall,
global cache reset, worker interruption or Git mutation. Phase not applicable.
Suggested commit: `Add a repeatable zsh iPhone release launcher`.

## App name — 9 November 2026

Goal/scope: rename the user-visible app to CD List on Flutter, macOS and iOS.
Keep bundle identifiers, Dart package name, project directories, icon and saved
data identity intact. One Dart appName constant supplies MaterialApp and toolbar.
iOS uses CD List for display/bundle name; macOS uses CD List as PRODUCT_NAME and
display name, including CD List.app, executable, window/menu identity. Update
macOS product/scheme/test-host references and current launch instructions.

Acceptance: CD List appears in the toolbar, macOS app identity and iPhone Home
Screen after native rebuild/update; live catalogue counts retain their suffix.
Existing saved data is associated with the unchanged identifiers. No broad
internal class/package/project rename or data migration.

Implemented and Dart formatted; native plist/project syntax checks passed.
Existing catalogue test title expectations updated; no new tests for this small
name change. Builds, tests, analysis, app launches and installs not run for this
request. Installed copies need rebuilding/reinstalling; source implementation is
complete and native acceptance pending. Report/files/manual commands:
outputs/app-name/README.md. No Git mutation. Phase not applicable.
Suggested commit: `Rename the visible application to CD List`.

Goal: one recognisable ammonite/headphone emblem matching the existing teal UI,
used in the app header and native macOS/iOS application identities, including the
macOS Dock, Finder and Command–Tab switcher.

Scope/tasks: generate original bitmap artwork with the built-in image tool;
retain the source in project outputs; export a committed 1024px master and app
header bitmap, macOS alpha/masked icon sizes and opaque iOS icon sizes from the
existing Xcode asset manifests. Provide a zsh regeneration command and standalone
ICNS. Keep native AppIcon asset settings and bundle identity intact. Do not change
functional navigation icons into branding or mutate a signed built app in place.

Acceptance: master/emblem consistent across header and native icon assets; every
manifest slot has correctly sized artwork; iOS images opaque; macOS icon has an
inset rounded tile; Command–Tab uses the rebuilt bundle AppIcon, not a Flutter
widget. Full rebuild/relaunch is required for native icon changes. Hot reload is
insufficient. Preserve app identity, transcript data and running worker jobs.

Done when artwork/export integration is complete and asset outputs inspected;
record verification separately from unrun Flutter analysis/builds and native UI
acceptance. Do not build/relaunch without explicit authorisation under AGENTS.md.
No API key or paid API fallback, external publication or Git mutation requested.

Implemented: generated original teal/ivory ammonite+headphones source, copied into
project outputs, exported 1024px committed master and 256px Flutter brand asset,
all existing macOS/iOS icon slots and standalone ICNS. Added zsh regeneration
script using CoreGraphics/ImageIO and iconutil; integrated header image and
pubspec asset. Visually inspected macOS rounded-tile preview and checked sample
sizes/alpha. Native build setting and existing built plist both use AppIcon.
Source prompt/mode
recorded in outputs/app-icon/PROMPT.txt; report in that folder's README.md.

No tests added (reversible visual change); no Flutter analysis/tests/builds or app
launch yet. Explicit rebuild/relaunch permission requested after installing the
reviewable assets, as required by AGENTS.md. No worker/job changes or Git mutation.
Native Command–Tab/Dock/iOS acceptance remains pending until rebuilt/relaunched.
Suggested commit: `Add Common Descent application branding and native launcher icons`.

David authorised macOS rebuild/relaunch (option 1). Debug build succeeded on
7 November 2026; old process exited and the rebuilt bundle launched/foregrounded
with a new PID. Built AppIcon.icns and NSRunningApplication.icon both visually
contain the new emblem. This did not establish actual Command–Tab display, and
David subsequently reported that the switcher still showed the default icon.
Current system appearance tints the NSRunningApplication icon. Independent
read-only audit confirmed all manifest slot sizes and iOS opacity. No Dock/cache
reset, worker interruption, tests/analysis or Git mutation. iOS source integration
is complete; device rebuild/install verification remains pending.

Follow-up: found an obsolete Release build registered with the same bundle ID
and its old Flutter icon. Keep the bundle ID stable; unregister that obsolete
build, register the current Debug build and set applicationIconImage directly
from this bundle's AppIcon.icns after Flutter's launch callback. Rebuild/relaunch
under the existing authorisation. Verify the runtime icon and native UI separately;
do not infer Command–Tab acceptance solely from NSRunningApplication.icon.

Follow-up implementation complete: direct native icon assignment added; debug
rebuild succeeded; stale Release registration removed and current Debug registered
and relaunched. Only Debug remains registered. Runtime icon visually inspected
and app window confirmed running. Command–Tab screenshot could not be obtained
through the UI tool, so actual switcher acceptance remains pending David's check.
No tests/analysis, worker changes, global cache resets, Dock restart or Git mutation.

## iPhone installation — 8 November 2026

David requested replacing the default icon on his phone, authorising the required
device rebuild/update. iOS source artwork and all AppIcon build settings were
already correct; the earlier asset work had not yet been installed on the phone.
Built and installed Release 0.1.0+1 in place on device
00008110-001E48A02187601E, retaining org.topository.commondescentlisting.
The compiled primary icon was visually verified as the ammonite/headphones design.

Flutter's wrapper failed with Xcode status 255. A direct build in iCloud project
work failed codesigning because FinderInfo metadata appeared on Flutter.framework.
Direct Xcode build using local DerivedData outside iCloud succeeded, followed by
successful device installation. No uninstall, bundle identity change or unrelated
source change. Launch was denied because the phone was locked; Home Screen visual
acceptance and opening the installed app remain for David after unlocking.
No tests/analysis or Git operations. Details and commands:
outputs/app-icon/IOS_UPDATE_2026-11-08.md.

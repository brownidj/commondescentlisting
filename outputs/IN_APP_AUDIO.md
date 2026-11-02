# In-app audio playback

Implemented 31 October 2026 as the authorised follow-up in
`plans/IN_APP_AUDIO_PLAN.md`. Implementation complete; native acceptance pending.

## Usage

Open an episode and choose **Play episode**. A persistent player appears at the
bottom, including on pages opened from News. It offers pause/resume, a seek
slider, elapsed/total time, back 15 seconds, forward 30 seconds and Close.
Click any available segment time to play that episode at the selected position.
For inferred news headlines, use **News section starts at …**: individual item
times remain unknown. The source-page and Apple Podcasts actions remain external
options; timestamps no longer hand off playback to Apple Podcasts.

Audio streams from the RSS enclosure over HTTPS. Internet is needed for audio;
the bundled catalogue remains available offline. One shared player continues
across navigation. Close stops playback. App shutdown releases native resources.
Playback position is not saved between app launches. This increment does not
provide downloads or background/lock-screen controls.

The saved RSS snapshot supplied audio for all 391 episodes. Its URLs were added
to the canonical YAML and identical bundled asset, preserving all 1,630 segment
records and their order. The generator now includes the optional `audio_url`
field on future exports. Older imported YAML still loads but cannot play unless
it supplies a valid HTTPS audio URL. If a saved import is active, reset to the
bundled catalogue or import an updated file to gain audio playback. Invalid or
credential-bearing URLs are not actionable; conflicting URLs for one GUID are
rejected. An audio failure leaves the catalogue available and can be retried.

## Implementation

Added `lib/services/playback_controller.dart`, `native_audio_engine.dart`,
`lib/widgets/playback_scope.dart` and `playback_bar.dart`. The controller is
application-owned and creates the native backend only on first playback.
Commands prevent competing loads, retain position on pause/resume, seek without
reloading the same episode, and clamp manual seeks/skips to available bounds.
The backend uses pinned `just_audio` 0.10.6 with iOS/macOS support:
https://pub.dev/packages/just_audio/versions/0.10.6

Modified the generator, both YAML copies, catalogue model/parser/repository,
app root, shared episode detail/cards, macOS client-network entitlements and
dependency files/plugin registration. Removed external timestamp-seeking logic
from the Apple Podcasts service; kept ordinary external episode opening.
No files removed and no Git actions performed.

Added controller and widget tests for initial segment seeks, same-episode seeks,
source changes, retry, bounded skips, completion replay, invalid/missing audio,
competing load protection and player persistence across routes. Updated parser,
repository and Apple Podcasts tests for the new behaviour.

## Verification

Completed: dependency resolution (`flutter pub get`) and Dart formatting.
Tests, Flutter analysis, native builds and app launches were not run for this
increment, following the project's manual verification default. Playback and
seeking are implemented but have not been verified by listening on either device.

Run in zsh from `flutter_app`:

```zsh
flutter analyze
flutter test
flutter run -d macos
```

A full restart/rebuild is required for the native audio plugin and entitlements;
hot reload alone is insufficient. For the authorised iPhone, use the device
deployment steps in `IOS_DEVICE_RUN.md` after running the checks above.

On macOS and iOS verify:

1. Episode 255 plays inside the app, with no Podcasts handoff.
2. News `00:05:25`, Part 1 `00:47:35` and Part 2 `01:16:05` change the playhead
   correctly and start audio; repeat while paused and while already playing.
3. Pause/resume, slider, skip controls, another episode, News navigation and Close
   work without simultaneous streams or position resets on simple navigation.
4. Offline audio failure leaves browsing intact; retry succeeds on reconnection.
5. Older imported YAML without audio still browses and reports audio unavailable.

Remaining limits: device listening, native build/signing, server range-request
behaviour and interrupted/poor-network playback need acceptance. Published
timestamps can differ from the audio when the publisher changes inserted ads.
No further platform work or publishing is included.

Suggested commit: `Add shared in-app episode audio player and segment seeking`.

## Overlay correction

David's macOS run reported `No Overlay widget found` from a player IconButton
tooltip. The player was a sibling of the Navigator in MaterialApp.builder, so
it could not access the Navigator's overlay. Added a shared PlaybackLayout using
Overlay.wrap around the Navigator and player. The app and widget test use this
same layout, and the test explicitly shows the Pause tooltip after starting
audio. The controller constructor now uses an initializing formal to resolve
the reported lint. Modified app.dart, playback_bar.dart, playback_controller.dart
and playback_widget_test.dart. Files formatted; no tests, analysis, builds or
app launches run by the assistant for this fix. No Git actions. Native acceptance
remains pending. David reported the three existing summary/storage tests passed.

Rerun from `flutter_app` in zsh:

```zsh
flutter analyze
flutter test test/features/episodes/playback_controller_test.dart test/features/episodes/playback_widget_test.dart
flutter run -d macos
```

Start audio and hover the player buttons to verify tooltip overlays and normal
play/pause/seek behaviour. Suggested commit: `Provide overlay for shared audio player controls`.

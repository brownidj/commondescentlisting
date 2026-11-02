# Apple Podcasts handoff

Current behaviour: Apple Podcasts remains a secondary external action. Segment
timestamps now use the in-app audio player instead of external timed links.
See `plans/IN_APP_AUDIO_PLAN.md`. The external seeking notes below record the
earlier implementation and reported limitations.

Implemented 31 October 2026, as an unphased enhancement.

Goal and acceptance: every episode details view on macOS and iOS offers an
Apple Podcasts action, including the shared view opened from News. Match exact
episodes by RSS GUID, retain the source-page action, and recover from launch
failure without losing the catalogue.

The new button opens the installed Apple Podcasts app, with a web fallback.
Apple Podcasts controls playback; the user may need to press Play there.
This does not embed audio. Segment timestamps can open a timed episode link.

Apple's public lookup returned the latest 200 episodes. Their GUID-to-Apple-ID
snapshot is bundled in `assets/data/apple_podcasts_episodes.json`.
Matched episodes show **Play in Apple Podcasts**. Other episodes show
**Find in Apple Podcasts**, searching by title without guessing an episode ID.
Imported catalogues also use GUID matching. The mapping needs a refresh as new
episodes are added; browsing itself requires no network connection.

Snapshot source:
https://itunes.apple.com/lookup?id=1207586509&entity=podcastEpisode&limit=1000

Files added: the snapshot, `lib/services/apple_podcasts.dart`,
`test/features/episodes/apple_podcasts_test.dart`, and this document.
Files modified: `pubspec.yaml` and `lib/features/episodes/episode_detail.dart`.
No files removed. No Git actions performed.

Verification: tests were added for exact GUID lookup, search fallback, and
recoverable handoff failures on both target platforms. Tests, analysis, builds,
and app launches have not been run for this enhancement, following the project's
manual verification default. Implementation is complete; native acceptance is
pending.

From `flutter_app`, run in zsh:

```zsh
flutter analyze
flutter test test/features/episodes/apple_podcasts_test.dart
flutter run -d macos
```

On macOS and the iPhone, check episode 255 opens the correct Apple Podcasts
episode. Check a news detail page does the same. Check an older unmatched
episode offers title search, and check the existing source-page action still
works. Launch and playback depend on Podcasts availability and network/downloads.

Suggested commit: `Add Apple Podcasts episode handoff on macOS and iOS`.

## Episode layout follow-up

The episode-page action now sits to the right of the Podcasts action in a Wrap,
with wrapping on narrow screens. Under Segments, a single News heading includes
the original news summary before the first news card; source segment order is
preserved. News cards omit their repeated type label and missing item-time
placeholder, while retaining actual item times and news-section times.
Only `episode_detail.dart` and `segment_card.dart` changed for this follow-up.
Both files were formatted. No tests, analysis, builds, or launches were run;
no tests added for this presentation change. Check both buttons at desktop and
phone widths, and confirm real timestamps remain visible. Unphased work;
implementation complete with visual verification pending.
Suggested follow-up commit: `Simplify episode actions and news segment labels`.

The discussion layout now has a single **Main discussion** heading before its
cards, following the news cards in the source catalogue. Discussion cards omit
both repeated type/label prefixes and display parts inline, for example
**Plant Origins - Part 1**. Applies to both episode browsing and details opened
from News through the shared view. Updated the existing episode-detail test
expectations for headings, inline parts and the removed news-time placeholder.
No tests, analysis, builds, or app launches run for this follow-up; manual
verification remains pending. Suggested commit: `Group main discussion parts under one heading`.

## Timestamp handoff

Known segment start times are now clickable on macOS and iOS when the Apple
snapshot contains an exact episode GUID match. A news card also offers its
news-section timestamp; this is the fallback when no item-specific time exists.
The link retains the episode ID and adds `t` in elapsed seconds, including zero.
Search destinations and missing times do not offer seeking. Launch failures use
the existing recoverable message. Both episode and News detail routes share
this implementation.

Apple documents sharing episodes at a starting time:
https://support.apple.com/en-au/guide/iphone/iph47499bcb5/ios
Apple's public web client also builds timed links with the `t` parameter:
https://podcasts.apple.com/assets/index~6d20381226.js

Modified `apple_podcasts.dart`, `episode_detail.dart`, `segment_card.dart`, and
the existing `apple_podcasts_test.dart`; no files added or removed. Added checks
for seconds conversion, zero/negative values, search exclusion and timestamp
handoff from both platform layouts. Formatted the affected Dart files. Tests,
analysis, builds and native app launches were not run for this change under the
project's manual-verification default. Implementation complete; actual seeking
on macOS/iOS is pending verification. Playback remains controlled by Podcasts.

From `flutter_app`, run:

```zsh
flutter analyze
flutter test test/features/episodes/apple_podcasts_test.dart
flutter run -d macos
```

On Mac and iPhone, open episode 255 and click news `00:05:25`, discussion Part 1
`00:47:35`, and Part 2 `01:16:05`. Confirm the correct episode and playhead time,
including when it was already playing. Repeat through a News detail page.
Also check that an unmatched older episode displays non-clickable timestamps.
Publishing and Git changes are outside this unphased enhancement.
Suggested commit: `Open Apple Podcasts at segment timestamps`.

### Reported resume behaviour

David reported that Podcasts resumes instead of seeking. Timed links now keep
their standard HTTPS shared-link format rather than first being rewritten to
`podcasts://`. Ordinary episode links retain the existing custom-scheme handoff.
This is a candidate compatibility fix, not a verified solution: launch success
does not confirm playhead position. Only `apple_podcasts.dart` changed in this
follow-up. No tests, analysis, builds or app launches run. Native macOS/iOS
acceptance remains pending, particularly for an episode already playing.
Reliable seeking controlled by this application would require an in-app audio
player; the external Podcasts app controls whether it honours a timed link.

# Episode 208 listener transcript

Prepared 31 October 2026 from the saved Whisper small.en result. This is a
contextual terminology review, not an audio-verified transcript.

## Deliverables

- `episode-208-karoo-reviewed.json`: authoritative reviewed text, cue IDs and
  unchanged millisecond start/end times, review status, unresolved flags, and
  before/after change records with reasons and confidence.
- `episode-208-karoo-reviewed.txt`: readable listener text, also copied to the
  project's `docs/transcripts/` alongside the untouched original.
- `episode-208-karoo-reviewed.vtt` and `.srt`: timed captions generated from JSON.
- `episode-208-karoo-changes.md`: human-readable correction audit by original cue
  number and time, with supporting evidence links from the contextual review.
- `corrections.tsv`: line-scoped literal replacements and review-group references.
- `build_reviewed_transcript.zsh`: repeatable generation from the baseline JSON.

All 63 High-confidence review groups were applied, affecting 168 of 1,032 cues.
The two Medium-confidence groups were not applied. Other words in affected cues
may have High-confidence corrections; retaining uncertainty does not freeze the
whole cue. Jokes, repetitions, grammar and historical scientific interpretations
are preserved. The name spanning cues 157–158 remains split at the same time.
Existing cue splits may still divide the words “super group”; no retiming or
merging of cues has been performed. This transcript is not guaranteed error-free.

The original `episode-208-karoo.txt`, `.json`, `.vtt` and `.srt`, the earlier review,
and `docs/transcripts/episode-208-karoo.txt` are retained. Do not edit the generated
TXT/captions or bundled asset independently. Update the scoped correction list
after review, then regenerate from the project root:

```zsh
./outputs/whisper-test/build_reviewed_transcript.zsh
```

## Listener experience

The app bundles the reviewed JSON for this exact episode GUID. Open Episode 208,
then **Read transcript**. The same action is available when arriving from News.
Reviewed text is the default; **Show original machine transcript** restores the
baseline text in the view without changing stored files. Unresolved notes appear
under affected passages. The label and limitations appear above the transcript.

With **Audio player** selected in Settings, select a passage to play at its start.
The current passage is highlighted when this episode is selected in the player.
With **Apple Podcasts** selected, the transcript remains readable and passage
seeking is disabled. The existing shared player remains across navigation.
The reader now follows the current passage automatically while this episode plays
in the in-app player; pause to browse freely. It does not claim word-level
synchronisation. See `TRANSCRIPT_AUDIO_SYNC.md` for the follow-up implementation.

This makes the transcript available in the next build of this app. Nothing has
been uploaded to Apple Podcasts, the publisher or any public transcript service.

## Verification status and handover

Generation completed; 1,032 cues and 63 applied groups were inspected in the output.
Cue start/end times match the original JSON exactly. The original TXT and its
docs copy retain their recorded SHA-256; the bundled JSON and docs reviewed TXT
match their generated sources byte for byte.
Flutter tests, analysis, builds and native playback were **not run** for this change.
Focused tests added cover baseline timing/original-text reconstruction, retained
uncertainties, wrong episode identity, invalid timing, original/reviewed display,
seek position, active cue and disabling seek for Apple Podcasts.

Code added: `flutter_app/lib/models/episode_transcript.dart`,
`flutter_app/lib/data/bundled_transcripts.dart`,
`flutter_app/lib/features/episodes/transcript_page.dart`, and the two focused test
files named below. Updated `episode_detail.dart` and `pubspec.yaml` to expose and
bundle the reader. The implementation plan is
`docs/plans/REVIEWED_TRANSCRIPT_PLAN.md`. Dart formatting was run on affected code.

From `flutter_app/`, David can run:

```zsh
flutter analyze
flutter test test/features/episodes/episode_transcript_test.dart test/features/episodes/transcript_page_test.dart
flutter run -d macos
```

Manual check: open Episode 208 directly and from News; read and toggle the original;
inspect flags around “drassic” and “castroides”; tap an early and a late passage;
confirm the intended audio position and highlight; navigate back with playback
continuing; repeat with Apple Podcasts selected; check a narrow iPhone layout,
large text, offline reading, and absence of a transcript button on other episodes.
Record the native environment and results before declaring playback verified.

Status: implementation complete; application verification pending. No existing
tests removed or changed, no files removed, and no Git actions performed.
Suggested commit message: `Add reviewed Episode 208 transcript and timed reader`.

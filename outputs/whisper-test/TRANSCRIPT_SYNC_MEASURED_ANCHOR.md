# Continued highlight lag — measured anchoring

Read-only inspection of the installed macOS app's Episode 208 correction journal
found `sync_offset_ms: 0` and three text revisions. No saved timing adjustment was
in effect. Its streamed audio URL also matches the URL recorded for the Whisper
trial. This does not establish that the media bytes or word alignment are identical.
The screenshot previously supplied matches the unadjusted cue timestamps, so
neither an offset sign reversal nor the actual speech-to-text delay is proven.
A player-time/spoken-passage pair has been requested to measure the discrepancy.
No running-app data was changed by the assistant.

Implemented an explicit anchoring action in the passage editor:

1. Find the passage you are hearing and open its pencil editor.
2. At the start of its words, press **Sync to audio now**. Audio continues from
   its current position; it is not rewound or advanced by this action.
3. The app saves `passage start − current audio position` as the episode offset.
   This replaces the previous offset, rather than repeatedly adding to it. When
   speech is ahead of the stored timing this produces a positive advance, and
   when speech is behind it produces a negative delay.
4. Close with Cancel if you are not editing text. The explicitly saved sync
   adjustment remains; text edits are saved only by Save. Reset timing in the
   transcript toolbar still returns the adjustment to zero.

The selected episode must be the one in the Audio player. Offsets over ±30 seconds
are rejected with a specific message. Save failures preserve the previous offset
and the text draft. Original text, cue timestamps and revision history are not
modified by anchoring. A single anchor is a constant offset; varying drift still
requires checking or aligning the cue timings against the audio.

The immutable edited transcript is now cached until text changes or a journal is
reloaded. Previously the whole cue list was reconstructed on every 100 ms player
notification. This removes unnecessary allocation during playback; no measured
performance benchmark or claim that this caused the reported lag is made.

Modified: transcript_edits.dart, transcript_editor_dialog.dart, their two focused
test files and the reviewed-transcript plan. No files removed, no transcript data
changed, no Git actions. Tests added for offset direction, repeated anchoring,
out-of-range anchors, failed saves, cache invalidation and UI anchoring without
audio seek/text save. Dart formatting was run. Tests, analysis, builds and native
listening checks were not run under the project's manual verification default.

From the project's flutter_app directory:

```zsh
flutter analyze
flutter test test/features/episodes/transcript_edits_test.dart test/features/episodes/transcript_editor_test.dart test/features/episodes/transcript_follow_test.dart
```

Manual checks: anchor a known spoken passage boundary; verify the highlight and
audio clock; replay that passage, reopen/restart, check a distant passage for
changing drift, and confirm text edits/history are retained. Record the measured
player time and actual spoken passage number before claiming the alignment fixed.
Status: implementation complete; reported alignment problem not yet verified
resolved. Suggested commit: `Add measured transcript sync anchoring and cache cue text`.

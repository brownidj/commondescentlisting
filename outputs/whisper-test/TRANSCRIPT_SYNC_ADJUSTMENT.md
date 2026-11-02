# Improving reported transcript lag

The supplied screenshot shows audio time 00:55:58 and highlights passage 554,
which starts at 00:55:57. The highlight agrees with the stored timestamps. The
image cannot establish where the spoken words actually occur. Whisper's timing
may be locally inaccurate; a different audio rendition can also have a different
offset. Neither cause has been verified by listening in this change.

Implemented:

- Native player position updates every 100 ms (the installed just_audio default
  stream's maximum period was 200 ms). This reduces display-update delay; it
  cannot alone correct several seconds of transcript/audio misalignment.
- **Adjust transcript timing** (sync icon) in the transcript toolbar opens saved,
  episode-specific calibration. Choose **Text earlier (+0.5 s)** when the audio
  is ahead of the highlighted words. Repeat until the highlighted passage matches
  what you hear. **Text later (−0.5 s)** reverses it; **Reset timing** returns to zero.
- Positive adjustment advances lookup to `audio position + offset`. Playing or
  replaying a passage uses `passage start − offset`, clamped to audio start, so
  clicking a passage remains consistent with the adjusted highlight.
- Calibration persists atomically alongside text corrections without changing
  their revision history. Old journals default to zero. Range: ±30 seconds.
  A failed save keeps the prior calibration and displays an error.
- Original passage timestamps remain protected. Export JSON records
  `playback_sync_offset_ms`; TXT/VTT/SRT and original cue timestamps remain unchanged.
  Other caption players do not automatically use this app-specific metadata.

No offset was guessed or applied to Episode 208 by the assistant. A constant
offset is useful when lag is reasonably consistent. If it changes across the
episode, accurate improvement requires checking/re-aligning the individual cue
boundaries against the audio; that work was not performed here.

Files modified: native_audio_engine.dart, transcript_edits.dart,
transcript_export.dart, transcript_page.dart and transcript_editor_dialog.dart
under flutter_app/lib/, two focused test files, and the reviewed-transcript plan.
No transcript text/times changed, no files removed and no Git actions performed.
New tests cover saved offset, inverse seek, failure rollback, preserved history,
export metadata, immediate highlighting and Reset. Dart formatting was run;
tests, Flutter analysis, builds and native listening checks were not run under
the project's manual verification instructions.

From the project's flutter_app directory:

```zsh
flutter analyze
flutter test test/features/episodes/transcript_edits_test.dart test/features/episodes/transcript_follow_test.dart test/features/episodes/transcript_editor_test.dart
flutter run -d macos
```

Manual check: listen near 00:56:00, adjust text earlier/later, replay the selected
passage and verify it starts where expected. Reopen/restart to verify persistence;
check another point earlier/later in the episode for changing drift. Verify local
corrections/history and search still work. Record environment/date/tester/results.
Status: implemented; automated/native verification pending. Suggested commit:
`Add persistent transcript sync calibration and faster position updates`.

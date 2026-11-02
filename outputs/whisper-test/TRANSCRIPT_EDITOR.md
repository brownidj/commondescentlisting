# Local transcript editor

Implemented 1 November 2026. Application/native verification remains pending.

## Making a correction

1. Open Episode 208 → **Read transcript**. Each timed passage now shows its number,
   matching the original TXT line numbers used in the correction review.
2. Select its pencil button. The editor shows the passage number and protected
   start timestamp. You can also search first, then edit a matching passage.
3. With **Audio player** selected in Settings, use **Replay passage** to play from
   its start and **Pause audio** when finished. Replay continues beyond the passage
   until paused; it does not loop or stop automatically at the end.
4. Correct the text and choose **Save**. The reader and search use the saved text
   immediately. Saving returns to the reviewed-text view. If the correction no
   longer matches the active search, the passage disappears from those results;
   clear the search to see it again.
5. **Cancel** discards the current draft. **Restore original** fills the draft with
   the original machine text; **Use bundled review** fills it with the supplied
   contextual review. Neither writes until Save. Empty passages cannot be saved.

The original-text switch always shows the original machine text, even after local
corrections. Editing starts from your latest saved reviewed text. Passage times
and IDs are never editable. Existing unresolved review notes remain visible;
local edits do not automatically declare those passages audio-verified.

## History and persistence

The transcript toolbar's **Correction history** action lists local revisions,
newest first. Expand a revision to see before/after text, passage number and time.
Restoring original text is also recorded when saved. Identical saves add no entry.

Corrections are stored in the app's persistent Application Support directory under
`transcript-edits/`, one episode-scoped JSON journal per GUID. They survive leaving
the reader, restarting and ordinary app updates with the same application identity.
They are local to the installation; uninstalling/removing app data or changing the
application identity can remove access. There is no cross-device sync.

The bundled asset, project transcript files, original Whisper outputs and TSV
corrections are not overwritten. A failed save leaves the previous saved transcript
in place and keeps the editor draft available to retry. Journals use a flushed
staging file and rename; interrupted staging files are ignored at startup.

If a saved journal is unreadable or a revised bundled transcript conflicts with
its passage text/times, the file is retained, the bundled text is shown, and editing
and export are disabled with a notice and retry action. The app does not discard
your history or silently apply it to different words/timestamps.

## Export

Use **Export reviewed transcript** in the transcript toolbar. This exports the
current saved edition, even if you are viewing the original text or search results.
It always includes the whole transcript, not just matching passages.

- **macOS:** choose a destination folder. A new `transcript-export-*` subdirectory
  contains all four formats. To keep project outputs together, choose
  `/Users/david/Library/Mobile Documents/com~apple~CloudDocs/PyCharm projects/CommonDescentListing/outputs/`.
- **iOS:** the share sheet offers the four files together. Choose **Save to Files**
  or another destination. Cancelling does not change saved corrections.

JSON retains original/bundled provenance, current text, cue IDs/times, unresolved
notes and the complete local revision history. TXT is readable text; VTT/SRT are
timed captions with unchanged boundaries. Caption exports flatten internal newline
characters to spaces; VTT escapes markup characters so literal text displays
correctly. Keep JSON as the complete correction backup. Importing exported JSON
through the app is outside this increment; the export is suitable for review and
future redistribution, and nothing is uploaded automatically to listeners or
Apple Podcasts.

Native export needs a fresh build: macOS user-selected-file access was changed
from read-only to read/write, and iOS has a share-sheet method channel. Hot reload
alone does not install native changes. No new package dependencies were added.

## Implementation and verification

Created:

- `flutter_app/lib/services/transcript_edits.dart`
- `flutter_app/lib/services/file_transcript_edits.dart`
- `flutter_app/lib/services/transcript_export.dart`
- `flutter_app/lib/features/episodes/transcript_editor_dialog.dart`
- `flutter_app/test/features/episodes/transcript_edit_test_support.dart`
- `flutter_app/test/features/episodes/transcript_edits_test.dart`
- `flutter_app/test/features/episodes/transcript_editor_test.dart`

Updated the transcript model and reader, existing transcript widget tests, iOS
AppDelegate, both macOS entitlements and the reviewed-transcript implementation
plan. No files removed, no transcript content edited, and no Git mutations.

Focused coverage added for save/reload/restore history, failed saves, invalid
text, malformed/conflicting journals, ignored staging files, consistent exports,
cancel/replay/pause, search following edits, history UI and export dispatch.
Dart formatting was run. Tests, Flutter analysis, builds, device launches and
native sharing were **not run** under the project's manual verification default.

From the project's `flutter_app/` directory, David can run:

```zsh
flutter analyze
flutter test test/features/episodes/transcript_edits_test.dart test/features/episodes/transcript_editor_test.dart test/features/episodes/transcript_page_test.dart test/features/episodes/episode_transcript_test.dart
flutter run -d macos
```

Manual checks on macOS and iOS: edit/cancel/save a passage; replay/pause; restore
original and bundled text; search for a newly saved word; inspect history; leave
the reader and restart to confirm persistence. Export all four files, check a
known late passage's text/time and original-text reconstruction in JSON. Test
export cancellation, Save to Files and iPad popover presentation; check keyboard,
large text and narrow layouts. Record environment/date/tester/results before
declaring native behaviour verified.

Status: implementation complete; automated and device verification pending.
Phase: not applicable (authorised follow-up). Suggested commit message:
`Add persistent transcript editing, revision history and export`.

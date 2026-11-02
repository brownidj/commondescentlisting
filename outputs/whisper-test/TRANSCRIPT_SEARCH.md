# Transcript search

Implemented as a follow-up to the reviewed Episode 208 transcript reader.

The **Search transcript** field stays above the scrolling text. Typing filters
passages by a case-insensitive literal phrase, ignoring outer query whitespace.
The count is the number of matching passages, not individual occurrences.
Matching text is highlighted; results retain transcript order and timestamps.
Scroll through results and tap a passage to play it using the Audio player.
Clearing the field restores the full transcript. **Show original machine
transcript** reapplies the current search to the original wording. No matches
displays **No matching passages**. Search does not inspect review notes or span
the boundary between two timed passages.

Playback follow-up: while this episode plays, its current passage remains visible
alongside matches even if its words do not match the query. A notice identifies
this extra passage; the match count still counts only genuine search results.
Pause to browse results freely. See `TRANSCRIPT_AUDIO_SYNC.md`.

Files created: `flutter_app/lib/features/episodes/transcript_search.dart` and
`flutter_app/test/features/episodes/transcript_search_test.dart`.
Files updated: `flutter_app/lib/features/episodes/transcript_page.dart`,
`flutter_app/test/features/episodes/transcript_page_test.dart`, and
`docs/plans/REVIEWED_TRANSCRIPT_PLAN.md`. No transcript data or files removed.

Focused tests cover case/whitespace, literal punctuation, occurrence ranges,
passage ordering, reviewed/original wording, empty/no-result queries, filtered
seek timestamps, retained review flags and clearing without disturbing playback.
Dart formatting was run. Tests, Flutter analysis, builds and launches were not run,
in accordance with the project's manual verification default.

From the project's `flutter_app/` directory:

```zsh
flutter analyze
flutter test test/features/episodes/transcript_search_test.dart test/features/episodes/transcript_page_test.dart
```

Manual checklist: search “Karoo”, try a phrase with punctuation, clear the query,
search an absent term, toggle original text, tap a late matching passage and
confirm its playback time. Check on macOS and iOS with large text and the keyboard
visible; drag the result list or submit the search to dismiss the keyboard.

Status: implementation complete; automated and native verification pending.
No Git mutations performed. Phase: not applicable (authorised follow-up).
Suggested commit message: `Add search within the transcript reader`.

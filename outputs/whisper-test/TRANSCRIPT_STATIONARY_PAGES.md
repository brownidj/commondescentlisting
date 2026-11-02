# Stationary transcript pages

The viewport now stays stationary while the highlight moves down the passages.
When it reaches the second-last fully visible passage, the page advances and the
previous viewport's bottom three fully visible passages become the first three
at the top. This replaces the earlier automatic per-passage re-centring, which
moved Sync targets on every transition.

Rows are measured after layout, including wrapped text, review notes and font
sizes. The review header is excluded from passage counts. With six full passages
visible, reaching number five advances so passages four, five and six start the
next page. No further automatic advance occurs at the end of the transcript.

When fewer than four passages fit, a three-passage overlap cannot also make
forward progress. The reader instead holds still until the active passage no
longer fits, then reveals it directly. Oversized passages stay stationary while
visible. Opening partway through an episode, distant seeks and resuming after
manual browsing still reveal the relevant passage; pausing permits free scrolling.
Search, direct passage Sync, player Edit, timing calibration and exports retain
their existing behaviour. No audio or transcript content/timestamps changed.

Modified transcript_passage_list.dart and the reviewed-transcript plan. Added
transcript_paging_test.dart covering stationary row/button positions, three-row
overlap, variable heights, small viewports, pause/seek and end-of-transcript
stability. Existing follow tests remain relevant. No files removed or Git actions.
Dart formatting ran. Tests, Flutter analysis, builds and native app launches were
not run under the project's manual verification instructions.

From the project's flutter_app directory:

```zsh
flutter analyze
flutter test test/features/episodes/transcript_paging_test.dart test/features/episodes/transcript_follow_test.dart test/features/episodes/transcript_editor_test.dart
```

Manual check on macOS and iOS: watch multiple passages on one page, confirm Sync
buttons stay still, and verify the bottom-three overlap when highlighting reaches
the second-last passage. Repeat with wrapped/large text, resize, search, pause,
seek and the final passages. Record environment/date/tester/results before
declaring native behaviour verified. Status: implementation complete; verification
pending. Suggested commit: `Page transcript with three-passage overlap during playback`.

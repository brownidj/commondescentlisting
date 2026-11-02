# Transcript load toolbar and test fixture fix

2 November 2026. Unphased fix; implementation complete, verification pending.

Goal/scope: address the two reported transcript_page_test failures. Acceptance:
episode replacement shows the new passage once and ignores stale completion;
Export is enabled immediately after successful transcript/journal loading and
opens the original-timestamps warning without unrelated UI interactions.

Modified flutter_app/lib/features/episodes/transcript_page.dart: install loaded
edits inside a synchronous setState block. FutureBuilder previously refreshed
the body while the toolbar remained disabled, because edits installation did not
rebuild its parent. Existing mounted/generation checks still reject stale loads.

Modified flutter_app/test/features/episodes/transcript_page_test.dart: give the
episode-switch fixture a label distinct from its passage text; assert Export is
enabled before tapping it. Existing warning/cancel and stale-load checks remain.
No tests/files removed. This report is new; no other files changed for this fix.

Formatting completed. Tests, analysis, builds and launches not run under AGENTS.md.
The user's preceding analysis output reported no issues before this change.
From flutter_app, run in zsh:

```zsh
flutter test test/features/episodes/transcript_page_test.dart
flutter analyze
```

Manual check: open a transcript and immediately select Export; confirm the timing
warning appears and Cancel avoids exporting. Also retry a failed load and switch
episodes. Record platform, tester, date and results. Done when these checks and
the affected tests pass. Remaining risk: runtime verification is pending.
No Git mutations. Suggested commit: Refresh transcript toolbar after load and fix fixture ambiguity

Follow-up on 2 November: David's rerun passed four tests and analysis, but the
new enabled-button assertion cast the byTooltip result (a RawTooltip in this
Flutter version) to IconButton. Changed only the test finder to select IconButton
by its tooltip property before inspecting onPressed and tapping. The application
code is unchanged by this follow-up. Formatting completed; assistant did not run
tests or analysis. Rerun the same commands above. Suggested follow-up commit:
Find transcript export IconButton directly in widget test

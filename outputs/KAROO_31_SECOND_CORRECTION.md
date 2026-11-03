# Karoo advertisement alignment — 2 November 2026

The new measurements supersede the single-point -7.942-second calibration.
Raw audio delays: passage 3 +30.247 s; passage 16 +31.001 s; passage 441 +31.069 s.
The median of these three is +31.001 s, giving app offset -31.001 s. Passage 1
(+33.262 s) has a suspicious 0–19.760-second span and is excluded. The earlier
passage-12 sample (+7.942 s) conflicts with the repeat observations; its cause
is not established. The close match at passages 16 and 441 supports a constant
offset through roughly minute 44, not proof of alignment through the ending.

Expected residuals with -31.001 s: passage 3 -754 ms, passage 16 0 ms, passage
441 +68 ms. These observations do not justify changing passage timestamps or
assuming an exact advert duration. Human marking and local timestamp error apply.

Changed flutter_app/lib/services/transcript_edits.dart: one maxSyncOffset constant
of 10 minutes governs journal loading, writes and direct Sync. The former 30-second
cap would have rejected the correct setting and prevented corrections loading.
Changed flutter_app/test/features/episodes/transcript_edits_test.dart: update old
range assumptions and add advert-length persistence, seek/highlight sign, unchanged
edits/timestamps, both boundary signs, and malformed persisted-range coverage.
Updated docs/plans/TRANSCRIPT_TIMING_DIAGNOSTICS.md. This handover and the backup
outputs/karoo-sync-before-31s-correction-2026-11-02.json are new; no files removed.

Changed the installed macOS Episode 208 journal from -7942 to -31001 ms. Preserved
all nine text revisions and every other JSON field, checked against a backup and
confirmed the journal was unchanged before atomic replacement. This setting is
local to macOS; no iOS or bundled defaults changed. Ad insertion may differ in a
future audio stream.

IMPORTANT: run the updated app before reopening the transcript. The old build
rejects adjustments exceeding 30 seconds. A full stop/start uses both the updated
validation and saved setting; hot reload alone may retain the previous value.
From flutter_app in zsh:

```zsh
flutter analyze
flutter test test/features/episodes/transcript_edits_test.dart test/features/episodes/transcript_timing_diagnostics_test.dart
flutter run -d macos
```

Check diagnostics shows -00:00:31.001. Passage 16 should start at 00:01:40.161;
passage 441 at 00:44:00.521 (68 ms before the measured click). Confirm edits remain
available, passage seeking and highlighting match the speech, and take a late
episode sample. Record tester, platform, date and results for native acceptance.

Dart formatting and JSON preservation checks completed. No tests, analysis,
builds, app launches or Git mutations performed, under AGENTS.md. Implementation
complete; runtime verification pending. Unphased work. Suggested commit:
Allow advert-length transcript calibration and preserve offset validation

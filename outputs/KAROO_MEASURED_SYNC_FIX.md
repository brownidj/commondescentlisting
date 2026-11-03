# Karoo measured calibration correction — 2 November 2026

Passage 12: stored start 42,920 ms, observed audio start 50,862 ms.
Correct offset = stored start minus actual audio start = −7,942 ms.
The old +6,004 ms setting made the adjusted clock 13,946 ms ahead at this point.

Changed only sync_offset_ms from 6004 to -7942 in the installed macOS app's
Episode 208 journal under the com.example.commonDescentListing container's
Application Support/com.example.commonDescentListing/transcript-edits directory.
Preserved all nine text revisions and every other JSON field. Validated JSON
against a backup and confirmed the source was unchanged before atomic replacement.
Backup: outputs/karoo-sync-before-2026-11-02.json. This report is the other new file.

Close/reopen the transcript page or restart the app to reload the saved setting.
An already open page retains its old in-memory calibration. The diagnostic panel
should show −00:00:07.942; passage 12 should highlight/start at audio 00:00:50.862.

Acceptance: this observation maps exactly to passage 12's stored start; revisions
remain intact. Arithmetic and JSON checks completed; native listening unverified.
No source or tests changed; no tests, analysis, builds, launches or Git mutations.
Unphased work. No commit needed for this runtime setting.

One sample cannot establish whole-episode alignment. Middle/end measurements are
still needed to check drift, local errors and further/different adverts. This
changes the current macOS installation only, not iOS or bundled defaults for
potentially different audio versions.

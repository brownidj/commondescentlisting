# Automatic catalogue update

Authorised 9 November 2026. Load the last valid local catalogue (bundle on first
launch), then refresh the configured central library or, without one, the official
podcast RSS feed. Display update stage and download progress; unknown lengths use
an indeterminate bar. Keep all cached episodes if RSS contains a limited window.
Validate complete metadata before atomic persistence and activation. Never download
audio or run preparation as part of this update. Offline/invalid responses retain
the previous catalogue with an explanatory notice. Dependencies use cached package
versions; no tests, analysis, builds or app launches without authorisation.

Acceptance: startup refresh works with and without a library setting; numbered,
side, news and discussion metadata remain compatible with the existing exporter;
empty/duplicate/malformed feeds cannot replace valid data; download sizes/time are
bounded; persistence failure retains current data; progress clears on every exit.
Supply focused parser and manager tests. Manual macOS/iOS/network acceptance pending.

Implemented: RSS metadata adapter and bounded download, GUID-preserving archive
merge, optional startup refresher on CatalogueManager, production library/RSS
selection and visible stage/progress. Added parser fixtures/saved-RSS compatibility
and manager save/fallback tests. Offline dependency resolution and formatting
completed; tests, analysis and native builds not run. See
outputs/automatic-catalogue-update/README.md for commands and acceptance checklist.

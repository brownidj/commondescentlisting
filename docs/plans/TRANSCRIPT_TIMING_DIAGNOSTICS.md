# Transcript timing diagnostics

Goal: measure whether transcript mismatch is a constant offset, drift, a timing
jump, or a display/clock problem, without modifying calibration or transcript data.

Scope/tasks: transcript-toolbar diagnostic dialog; live raw/adjusted audio clock,
saved offset and highlighted cue bounds; select a passage by number; mark its
spoken start; retain measurements for the page session; copy a JSON report.
Include playback and seek controls for sampling different parts of the episode.

Acceptance: capture clock at the click, independently of edit/highlight selection;
record stored start, actual audio position, raw difference, calibrated residual,
highlighted passage and playback status. Disable marking for another episode,
paused/buffering/busy/failed playback, or an invalid passage. Marking never writes
calibration, edits, seeks or changes playback. Report times in integer milliseconds
with a clear sign convention. Display raw difference range after multiple samples
without claiming automatic diagnosis from human measurements. Preserve samples
when reopening the dialog, separated by episode; copying supports sharing results.

Done when implementation and focused tests are supplied, then David verifies the
tests and native measurement workflow. Implementation and verification status
are separate; tests/analysis/builds/launches remain manual under AGENTS.md.

Measured correction follow-up, 2 November: repeated Karoo observations support
an approximately 31-second delay. Raise the single shared calibration bound to
10 minutes in read validation, writes and passage anchoring so introductory
advertising can be accommodated. Apply -31,001 ms to the current macOS journal,
preserving text/history. Do not impose a bundled default on other streams/devices.
Acceptance: offsets beyond 30 seconds survive reload and affect seeking/highlights
with the existing sign convention; limits are consistent, excessive adjustments
remain rejected, and text/history/timestamps stay unchanged. Add focused coverage;
runtime verification remains pending a new app run by David.

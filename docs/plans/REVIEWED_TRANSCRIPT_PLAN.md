# Reviewed listener transcript — Episode 208

Authorised 31 October 2026. Apply PROGRAMMING_CRITERIA.md.

Goal: provide a separate, context-reviewed listener transcript while retaining the
original Whisper outputs as the transcription baseline.

Scope: apply only High-confidence entries from the existing contextual review;
retain Medium-confidence and unresolved wording. Keep cue boundaries and times.
Use one reviewed JSON as the source for TXT, VTT, SRT and the bundled app asset.
Record each changed cue, the original/replacement text, times, confidence and
review reason. Copy the reviewed TXT to docs/transcripts alongside the original.

App: offer a transcript on the matching episode GUID, including News navigation
to that episode. Display the review label and unresolved passages separately.
Highlight the active cue for this episode in the in-app player; tapping a cue
plays that episode at its unchanged start time. Apple Podcasts users may read
the transcript, but seeking is available only with the Audio player setting.
No automatic scrolling, transcript search, downloads, publisher upload or
transcripts for other episodes in this increment.

Acceptance: original files unchanged; 1,032 reviewed cues with identical timing;
all applied changes traceable to High-confidence review entries; uncertain cases
flagged without substitutions; formats generated from reviewed JSON; transcript
loads offline and only for its exact episode; missing/invalid assets fail safely;
seeking uses the existing shared player and preserves navigation behaviour.

Done when implementation and deliverables exist, with verification status stated
separately. David runs the focused Flutter tests, analysis and native playback
checks. No Git changes or publication are authorised.

## Follow-up: transcript search

Authorised: add search within transcript mode. Search the currently displayed
reviewed or original wording using a trimmed, case-insensitive literal substring.
Keep the search field visible while scrolling. Show matching passages in their
original order, a passage count, highlighted matches, clear and no-results states.
Clearing restores the full transcript; changing text mode reapplies the query.
Keep review notes, original cue IDs/times and tap-to-play on matching passages.
Search is within individual passages, not across cue boundaries or review notes.

Tasks: shared matching helper, reader controls/filter/highlighting, focused tests.
Acceptance: literal punctuation is safe, case and outer whitespace do not affect
matches, original/reviewed searches differ appropriately, clearing restores all
cues, and filtered playback seeks to the correct original timestamp. No changes
to the transcript data. Implementation and verification status recorded separately;
David runs Flutter analysis, focused tests and native manual checks.

## Follow-up: local transcript editor (1 November 2026)

Goal: correct passages while listening without rebuilding the app. Scope: passage
number/time, replay and pause, multiline text editor, Save/Cancel/Restore original,
local revision history, persistent overlays on the immutable bundled transcript,
immediate reader/search updates, and JSON/TXT/VTT/SRT export. Timestamps cannot be
edited. Restore original fills the editor and requires Save. History includes
restores. macOS chooses an export folder; iOS uses its share sheet/Save to Files.

Tasks: validate and atomically persist an episode-scoped revision journal in app
support; keep edits when navigating/restarting; reject malformed/stale journals
without overwriting them; add editor/history UI and export serializers and native
iOS sharing; add focused tests and operating instructions.

Acceptance: failed saves keep the prior reader and draft; cancel writes nothing;
reloading restores changes and history; empty text rejected; original text always
available; filtered cues retain identity; searching follows saved edits; all four
exports share cue text/times and JSON retains provenance/history. Source changes
that conflict with a journal block further editing rather than discarding it.
No network publishing, sync or automatic audio verification. Native playback,
permissions, iOS share sheet and persistence need David's manual verification.
Done when implemented with verification status recorded separately; tests,
analysis, builds and launches remain for David to run.

## Follow-up: always follow playing audio (1 November 2026)

Goal: keep the currently spoken passage visible while the in-app player is playing
this episode. Tasks: time-to-cue lookup, an indexed lazy transcript list that can
jump to distant variable-height passages, and playback/search integration.
Always follow while playing, including after seeks, manual scrolling, resuming
and opening the reader partway through an episode. Stop automatic scrolling when
paused or playing a different episode. Keep the active cue in filtered results
even if it is not a search match, with a clear notice and unchanged match count.
Do not clear the query or change text/timestamps. Retain original/reviewed modes,
local editing, replay and export. External Apple Podcasts has no position stream
available to this app; follow applies to the in-app Audio player.

Acceptance: current passage is highlighted and visible, even for a long-distance
forward/backward seek; no whole-transcript eager build or new dependency; cue
boundaries are start-inclusive/end-exclusive, with no invented cue in timing gaps;
paused scrolling stays free; resuming follows again; active search does not hide
the playing cue. Add focused timing and widget coverage and handover. Tests,
analysis, builds and native runs remain for David unless separately authorised.

## Follow-up: reported highlight lag

The screenshot's highlighted cue matches the displayed clock; the reported
speech/text discrepancy is not measurable from the image alone. The installed
just_audio default stream has a 200 ms maximum interval. Improve responsiveness
with a 100 ms position stream and add a per-episode adjustable display offset
(positive = text earlier). Keep its default at zero; do not guess an offset.
Persist it atomically alongside the correction journal, including legacy journals
without it. Range ±30 seconds, UI steps 0.5 seconds, Reset to zero. Use the inverse
offset for passage play/replay; clamp negative audio seek targets to zero. Retain
original timestamps and export the calibration as JSON metadata, not rewritten
caption timing. Add focused persistence, failed-save, lookup/seek and UI tests.
Acceptance: changing offset updates highlighting immediately, survives restart,
retains edits/history, and is isolated to this episode. Document that a constant
offset helps consistent lag; varying local alignment errors need audio alignment
work beyond this change. Tests/analysis/native listening remain for David.

## Follow-up: continued lag report

Read-only inspection found Episode 208's local journal has zero sync offset.
There is no evidence of a reversed saved offset, and faster repainting cannot
fix several seconds of source alignment error. Ask for a player-time/spoken-cue
pair to measure it. Add an explicit editor action to align the selected passage
start with the current audio clock without seeking or changing text/timestamps.
Require the same episode in the player, persist atomically, retain the existing
±30 second guard and report errors accurately. Explain to press at the start of
the passage and that timing saves immediately, separately from the text Save.
Cache the immutable edited transcript until its text changes so the 100 ms
position stream does not reconstruct every cue. Add regression coverage; do not
claim that measured audio alignment has been fixed without a timing pair/native
listening evidence. No tests, builds or app launches without authorisation.

## Follow-up: stationary transcript pages

Replace per-passage re-centring with page-style following. Keep the page stationary
as highlighting advances. On reaching the second-last fully visible passage,
advance with the previous viewport's bottom three fully visible passages at the
top. Measure actual laid-out rows so wrapping, notes and enlarged text are counted
correctly; header is not a passage. Do not advance repeatedly at the end of the
transcript or when three-row overlap cannot produce forward progress. For very
small viewports, reveal directly only when the current passage is no longer
visible. Distant seeks/opening mid-episode still reveal the active passage;
pausing retains free scrolling. Keep lazy construction and passage Sync/Edit.
Acceptance: early highlight changes leave row and button coordinates unchanged;
threshold paging retains three rows at the new top; resizing, long rows, seeks,
end-of-transcript and pause/resume do not cause endless repaging. Add focused
widget coverage and manual handover; tests/analysis/native runs remain for David.

Test-flow correction (3 November 2026): the combined editor/export widget test
must acknowledge the existing Export timing confirmation before expecting its
export callback. Assert that no export occurs while the dialog awaits a choice,
then select Continue exporting and retain all four-file/content assertions.
Product behaviour stays unchanged; manual rerun of transcript_editor_test.dart
is the acceptance check. No automatic tests/builds/analysis or Git mutation.

Display update (3 November 2026): removed the Audio position subtitle from the
playing passage. Preserve playing/editing highlights, selected-for-editing text,
review notes and player controls; omit an otherwise empty subtitle. Updated the
existing playback interaction expectation. Both Dart files formatted. Tests not
run; manual acceptance: flutter test test/features/episodes/playback_interactions_test.dart,
then confirm playback highlighting still advances without the extra label.

Selection controls update (3 November 2026): remove passage Sync icons and both
selection-status text rows. A selected-for-editing passage alone gets a far-right
pencil opening the existing editor. Right-click/long-press that passage again
clears selection; choosing another passage changes selection without seeking.
Keep distinct playing/editing highlights, review notes, toolbar editing and
pause/replay/bookmark restoration. Remove the unused passage-sync handler, leaving
Nudge/diagnostics intact. Update existing integration expectations for the new
selection/pencil gestures. Acceptance: one selected pencil, no sync/status text,
right-click toggle leaves audio/time/journal unchanged, pencil pauses and Cancel
restores playback. Formatting only by assistant; affected tests run manually.

# In-app episode audio

Authorised 31 October 2026. Follow PROGRAMMING_CRITERIA.md.

Goal: play and seek episode audio under this app's control on macOS and iOS.

Scope: optional audio_url from RSS enclosures in YAML; backward-compatible
loading; one shared player across episode/news navigation; play/pause, position,
duration, seek slider, skip back/forward, close, loading and recoverable errors.
Segment timestamp clicks select the episode and start at that time, using the
news-section timestamp when individual news timing is absent. Retain external
episode/Podcasts actions as secondary options. Streaming requires connectivity;
catalogue browsing stays offline. No downloads, background/lock-screen controls,
or persisted playback position in this increment.

Tasks: enrich generator and saved catalogue; validate URLs; add just_audio native
backend with testable shared controller; add persistent controls; wire timestamp
actions; enable macOS network client access; add focused tests and handover.

Acceptance: one active audio stream, correct source and initial position on
episode changes, repeated seeks on the same episode, pause/resume without reset,
navigation retains playback, failures remain retryable, old YAML without audio
still browses, missing/unsafe audio cannot play, close/dispose frees resources.

Done when implementation is complete and verification evidence is recorded
separately. Tests, analysis, builds and launches follow the manual-verification
default unless David authorises them. Native listening and timestamp checks on
both targets remain required before claiming verified playback.

Follow-up: add a Settings icon on the catalogue page, persist the listener's
choice of Audio player or Apple Podcasts, and route a single episode Play
button accordingly. Stop current in-app audio when changing player; show the
persistent controls only for Audio player. Remove the general Original news
summary expansion row, retaining raw data and the selected-news context view.
Acceptance includes preference restoration, failed-save recovery, no concurrent
in-app audio after switching, and the same Play behaviour from News details.

Follow-up: move the transcript timing Sync control from the transcript toolbar
to the far right of the player's segment row. Keep segments horizontally
scrollable on the left and Sync fixed on the right on narrow and wide layouts.
Use the existing transcript timing panel and saved adjustments. Route registration
must be removed on disposal; disable Sync when the player's episode differs from
the open transcript. No change to timing calculations or audio. Add focused widget
coverage; David runs tests/analysis and native layout checks.

Superseding UI request: remove player Sync. Put an icon-only Edit button at the
far right of the segment row; it resolves and edits the highlighted passage at
click time. Replace every passage pencil with a Sync icon that immediately anchors
that passage to the same episode's current audio position, without opening an
editor or seeking. Disable Edit without an active highlighted passage; disable
Sync for a different episode or during a pending save. Retain persistence/history,
audio-follow and search. Remove the old timing panel and duplicate editor sync
action. Cover direct sync, click-time editing, wrong-episode/absence, layout and
lifecycle. Tests/analysis/native checks remain manual.

Follow-up: Space toggles in-app pause/resume except while typing in editable
fields, with key repeats/modifier combinations ignored. Left-click a transcript
passage or player segment to play from its start. Right-click a passage selects
it for the player Edit action without seeking or changing playback; selection
holds the page until cleared, played or the editor closes. Keep the playing cue
separate from edit selection. Replace the clock under the slider with the current
audio passage number/count, using calibrated transcript timing and retaining
loaded transcript metadata after navigating away. No invented passage when data
is missing or timing is in a gap. Add focused interaction/state coverage. Tests,
analysis, builds and native keyboard/mouse checks remain for David.

Follow-up: distinguish the audio-position highlight from the edit selection.
Right-click selects for editing without seeking or pausing. Edit captures the
current listening position and playing state, pauses, and opens the selected
passage. Replay inside the editor is temporary; Save, Cancel or dismissal returns
to the captured position and resumes only if previously playing. A silent preview
must remain silent without loading audio unless Replay is used. Restoration waits
for pending Replay loading; an explicitly closed or changed episode is respected.
Acceptance: simultaneous distinguishable highlights, selection without audio
movement, pause on Edit, restoration after Save/Cancel, paused-state preservation,
and no unnecessary audio load. Implementation and focused coverage added;
verification remains pending David's tests and native listening checks.

Follow-up: in transcript mode show “‹ Nudge ›” in the player on the passage-number
row. Left retreats the calibrated transcript clock by 500 ms; right advances it
by 500 ms. Save the offset through TranscriptEdits without seeking/pausing audio
or changing original cue times/text. Reuse visible reader action registration;
hide outside the reader, disable for a different episode or pending/conflicting
save, editing/export/diagnostics, and prevent crossing calibration bounds.
Acceptance: same-row phone/desktop layout, exact signs and 500 ms increments,
persistent offset and updated passage highlight, unchanged audio position/state,
failed-save recovery and route cleanup. Done when focused widget coverage and
manual listening/layout checks pass. Implementation complete; verification pending.

Episode actions refinement — 3 November 2026: Play becomes an icon-only filled
button with a Play tooltip/accessibility label. Rename Open episode page to
Episode page and Prepare episode to Prepare transcript. Place those two actions
at the far right of the same row as Play. Preserve Read transcript separately.
Use horizontal scrolling if narrow/enlarged text cannot fit that single row.
Keep playback destination, preparation and page-opening behavior unchanged.
Done when implementation and existing selectors are updated and formatted;
David checks affected widget tests and narrow/wide layouts. No automatic tests,
analysis, builds or launches.

News heading controls — 3 November 2026: move shared news-section timestamp and
play action from individual News cards to the News heading, labelled “- starts
at HH:MM:SS”. Use the first known newsStartTime, falling back to a section-only
News record's startTime (never an individual headline start). Reuse existing
in-app playback availability rules. Hide timing/play actions inside all News
cards; discussion cards retain their existing actions. Wrap heading controls on
exceptionally narrow/enlarged layouts. Update affected widget expectations;
format only and leave test execution/manual layout/playback checks to David.

Episode action tooltips — 3 November 2026: remove the inline automatic-news
notice; show that same text as Episode page's tooltip. Prepare transcript gets
a tooltip explaining preparation may take some time and automatic transcription
will probably not be 100% accurate. Preserve actions and availability. Update
existing notice assertion to check tooltip configuration and no inline text.
Formatting only; manual hover/long-press and widget verification remain pending.

Episode actions follow-up — 3 November 2026: place Episode immediately after
Play on the left. Keep Prepare transcript on the right, followed by Transcript
when available. Rename Episode page and Read transcript accordingly, preserving
tooltips, actions and platform availability. Retain horizontal scrolling on narrow
layouts. Done when source and existing selectors are updated and formatted;
manual layout, navigation and widget checks remain for David.

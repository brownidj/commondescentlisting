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

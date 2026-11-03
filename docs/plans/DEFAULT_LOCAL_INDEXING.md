# Default local indexing after episode preparation

Authorised 4 November 2026. New preparation workflow: download/reuse audio,
encode, transcribe, align, prepare local categorized index, then report details.
Use existing offline GLiNER model/cache and shared vocabulary; never call paid
APIs or silently install dependencies. Preflight before expensive audio work.

Run local indexing before worker edition activation, retaining prior edition on
failure. Store edition/text-bound index sidecar with checksum and summary; include
it in resumable checkpoints without modifying immutable audio/transcript manifest.
CLI registration aggregates sidecars into a separate local asset; worker exposes
only allowlisted sidecar and app merges local suggestions with existing API/manual
entries. Keep all five categories and review/CAS protections; no invented author
links. Filter obvious pronouns, host names, promotional platform/time-as-place
candidates. Publication detection remains provisional and may be incomplete.

Report episode, model/method, passages, audio size, category counts, time, output
paths and no paid API use. Completion dialog reports local indexing counts.
Acceptance: no complete/activation until index succeeds; exact GUID/edition/text
anchors; app discovers CLI/worker indexes; old packages still load; summaries and
failure are explicit. Add focused coverage; existing authorisation covers index
tests and analyzer, not full preparation/transcription or native launches. A local
index-only trial against an existing package is in scope; do not retranscribe.

Implemented. Index-only India trial completed offline (1,670 passages; 627
provisional candidates; 12.75 seconds). All 29 focused index tests passed and
analyzer clean. Script syntax/embedded Python compiled; literal anchors checked.
No full download/transcription/activation or native app launch performed. See
outputs/DEFAULT_LOCAL_INDEXING.md for files, report paths and acceptance limits.

# Transcript library and knowledge indexes

## Goal
Browse/search available transcripts and separate indexes of fossils, places,
papers, articles and shared authors, linking each occurrence to corrected passages
and the exact audio edition.

## Scope and tasks
- Shared immutable entity model: stable ID, kind, name, aliases, review state,
  place subtype; publication year/journal/publisher/DOI/URL and ordered author IDs.
- Offline seed vocabulary proposes names; match whole terms in current saved
  corrected passages. Suggest literal DOIs as unverified references. Do not invent
  publication titles, author relationships or external metadata. User can add,
  edit, confirm/reject entities, assign ordered authors and verified links.
- Persist registry with compare-and-swap, preserving concurrent edits. Derived
  occurrences rebuilt from current transcript editions/corrections, not guessed
  or stale timing. Failed transcript loads visibly reported, never silently skipped.
- Indexes navigation: searchable/sortable categories and transcript library,
  status filters, quotations, episode/passage/time, Open passage and Play.
  Author entries link back to publications; publication entries link ordered authors.
- Reload on preparation changes, returning from correction UI, explicit Refresh,
  and app/tab return. Preserve review state across retranscription; recompute hits.
- Open passage without seeking; Play uses current saved offset and fixed audio
  identity; disable with mismatched/unavailable recording or Apple Podcasts mode.
- Local data export/import for backup/transfer with schema validation.

## Acceptance / done when
Indexes populate from available bundled/local transcripts; aliases/word boundaries,
duplicates, rejection/review, author order, invalid references, stale editions,
load failures and persistence conflicts have focused tests. No network inference
or paid API. Format code; tests/analyze/build/native checks remain David's manual
steps. State implementation versus verified status honestly. No Git mutations.

Manual: verify macOS/iOS navigation/search, add/confirm/reject entries, author
links and publication metadata, edit passage and return, prepare another edition,
refresh, offset-aware Play and Open passage, backup/import, narrow/large text.
Record tester/date/environment/results before claiming verified.

## Implementation status — 3 November 2026
Implemented with offline candidate suggestions and explicit human reference review.
No external recognition/bibliographic API or new dependency. Device-local atomic
registry; derived in-memory word postings and occurrence data; JSON backup/import.
App starts index work only when Indexes is selected. Publication metadata absent
from wording remains unknown. Open passage holds reader context until Follow audio;
Play reloads current adjustment/edition and checks audio identity. Added focused
engine/controller/browser/deep-link coverage. Dart formatted, tests/analyzer/builds
and native acceptance not run. See docs/TRANSCRIPT_INDEXES.md and
outputs/TRANSCRIPT_INDEXES.md for file inventory, commands, caveats and checklist.

## Duplicate headings after contextual review — 4 November 2026

Merge exact normalized headings within each category, combining aliases, evidence,
details and author links. Prefer existing human-reviewed records; retain their
IDs and persist absorbed IDs so refresh cannot recreate duplicates. Normalize
whitespace and case, but do not merge merely similar names or different categories.
Preserve conflicting rejection decisions and bibliographic identifiers, dates or
publication metadata. Apply to the current macOS registry through its locked
compare-and-swap store, with a backup; leave source suggestions/evidence intact.
Acceptance: one arachnids heading with all references; duplicate taxonomy, place,
author and compatible publication headings combine; refresh is idempotent;
independently identified works and different categories remain distinct. Existing
focused index-test/analyzer authorization applies; no API requests or Git actions.

## Compact Indexes toolbar — 4 November 2026

Move catalogue provenance/counts, available transcript/contextual-match counts and
entry guidance into one tooltip on the Indexes heading. Hide the catalogue summary
banner only while Indexes is selected, retaining notices and error details and the
existing banner on Episodes/News. Put category, search and scope on a single row;
allow horizontal scrolling at narrow widths rather than clipping controls. Replace
the alphabetical sort icon/text duplication with “↕ A–Z” (and “↕ Z–A” when reversed).
Acceptance: correct live counts/provenance in tooltip, no duplicate visible status
text, one-row controls, working category/search/scope/sort and no narrow overflow.
Use existing focused UI/index-test and analyzer authorization; no API/Git actions.

Compact toolbar implemented: shared banner hidden only on Indexes, live status
and guidance in its heading tooltip, one-row horizontally scrollable filters,
“↕ A–Z”/“↕ Z–A” sort toggle. All 13 affected browser/catalogue tests passed;
analyzer clean. Native manual visual acceptance pending. No worker changes,
API calls, builds/launches or Git actions. See outputs/index-toolbar/RESULTS.md.

## Compact entries and fixed toolbar — 4 November 2026

Keep each entry heading followed by category and grouped reference count. Remove
its repeated category/subtype/review subtitle and expanded review prose. Move
spoken wording, confidence, description, normalization caveats and review/model
information into a tooltip on the entry heading. Keep quoted references, source
links/bibliography and explicit review navigation available. Preserve the full
review page for editorial work. Keep Indexes heading, filters and actions through
Import fixed; scroll only results and any result diagnostics. Acceptance: heading
and category/count visible, tooltip retains review information, references and
accordion/navigation still work, toolbar coordinates remain fixed after scrolling
many results, narrow view has no overflow. Existing focused-test/analyzer approval
applies. No API/Git/build/launch operations.

Compact entries/fixed toolbar implemented. Entry provenance is in title tooltips;
category and grouped reference count follow each heading. Filters and actions
remain outside the results viewport. Full review navigation and sources retained.
All 38 focused index tests passed and analysis is clean; native manual visual
acceptance pending. See outputs/index-toolbar/COMPACT_ENTRIES.md. No data, worker,
API or Git operations for this UI task.

Entry tooltip follow-up: mount provenance tooltips only for the currently expanded
entry. Collapsing or switching entries disposes the old tooltip; the Indexes
heading tooltip remains available. Extend compact-entry/accordion coverage for
closed, opened, switched and collapsed states. No data or worker changes.

## Confirmed index deletion — 4 November 2026

Show Delete at the far right of the A–Z/action row only for a visible expanded
entry. Ask “Are you sure?” with No/Yes; dismiss/No never modifies data. Yes uses
the displayed entry ID and captured registry revision, saves atomically with CAS,
clears expansion, and removes obsolete author links. Preserve a serialized deleted
marker and all merged variant IDs so refresh/import/export cannot resurrect source
suggestions. Deleted entries never appear in any filter or occurrence result;
transcripts stay untouched. Preserve independent concurrent changes. Acceptance:
button visibility/alignment, cancellation, confirmed removal, refresh and backup
persistence, merged-source suppression and safe stale/conflicting-save rejection.
Use existing focused-test/analyzer authorization. No actual entries are deleted
while implementing/testing; use isolated fixtures. No API or Git mutations.

Manual and legacy entries also use the accordion so every entry exposes the same
Delete action; their full review page remains reachable through Review entry.

Confirmed deletion implemented. Delete is conditional and right-aligned; No/dismiss
makes no change and Yes uses revision-protected persistence. Deleted markers and
merged IDs survive refresh/backup; obsolete author links are removed. All 43
focused index tests passed; analyzer clean. No live entries deleted in development,
native manual acceptance pending. See outputs/index-toolbar/DELETE_ENTRIES.md.

## Bulk index deletion — 4 November 2026

Goal/scope: add deletion checkboxes to all index categories, including Places.
Checkbox gestures must not expand/collapse an entry. Keep Delete visible at the
far right of the action row, disabled until at least one entry is marked.
Confirm the marked count/names with Are you sure? No/Yes; Yes deletes all marked
IDs in one revision-protected atomic registry save, preserving tombstones,
merged IDs and author-link cleanup. No/dismiss leaves marks and data unchanged.
Changing category, search, scope or review filter clears marks to avoid hidden
selections; sorting preserves marks. Existing entry expansion is independent.

Acceptance: zero/one/multiple selection enablement, checkbox does not expand,
cancel preserves entries, confirmed bulk deletion survives refresh, unselected
entries remain, stale/missing/conflicting saves cannot partially delete, toolbar
remains fixed. Updated browser and deletion fixtures; verification remains manual.
Implementation complete; tests/analyzer/native acceptance not run this turn.

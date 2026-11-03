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

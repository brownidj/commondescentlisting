# Transcript library and knowledge indexes

## Search field tooltip — 9 November 2026

Goal/scope: remove the visible index-first helper line beneath Search in
transcripts and put the exact text `Searches indexes first` in a tooltip on that
field. Keep the field key and all search/fallback behavior. Implemented in
episode_browser.dart. Acceptance: no helper line; hover/long-press reveals the
tooltip, and entering/clearing/submitting still works. Dart formatted; no tests
added for this reversible visual edit, and tests/analysis/builds/launches not run.
Manual commands/checklist and file record: outputs/episode-search-and-sorting/README.md.
No Git mutations. Phase not applicable. Suggested commit:
`Move transcript search guidance into a tooltip`.

## Catalogue heading follow-up — 7 November 2026

Goal/scope: remove the visible catalogue provenance/count banner and consolidate
live totals in the main app title row:
`Common Descent Listing - <n> episodes and <n> news`.
Latest follow-up moves the counts out of the episode column, leaving Search
episodes first in that column. Keep the title/counts on one row with ellipsis
when space is constrained.
Follow-up: use lowercase labels and reduce the previous headlineSmall size by
4 logical points (24 → 20 with the default theme), preserving theme styling.
Use total loaded catalogue counts, retaining the separate filtered-result count.
Preserve notices, diagnostics and the existing Indexes tooltip provenance.
Acceptance: no static Bundled catalogue/Saved local catalogue summary above pages;
the app title reflects imports/reset, fits narrow layouts, and notices
still appear when needed. Done when implementation and existing test expectations
are updated; runtime acceptance remains a separate manual check.

Implemented in catalogue_status.dart, catalogue_shell.dart and episode_browser.dart;
existing catalogue_manager_test.dart assertions updated. Dart formatted. No new
tests/files removed; tests, analysis, builds and app launches not run. Manual:
verify title-row counts after import/reset, narrow truncation, News/Indexes
without a duplicate banner, and diagnostic notices. Commands/report are in
outputs/episode-search-and-sorting/README.md. No Git actions. Phase not applicable.
Suggested commit: `Consolidate catalogue totals in the Episodes heading`.

## Episode search and filing update — 7 November 2026

Goal: separate episode-title search from an index-first transcript lookup, with
an explicit fallback and reviewed adoption of useful missing index terms.

Scope/tasks: show Search episodes above Search in transcripts; remove the search
target dropdown. Combine the two independent queries with the episode filter.
Search existing index names, aliases, authors and references first. When no
filtered result exists, ask before searching current corrected transcript text;
ask separately before adding found passages. Reuse IndexEntityDialog for category
and metadata review, save through the existing atomic registry/heading/plural/
author reconciliation rules, and preserve exact edition/passage/text evidence.
Revalidate editions and registry revision before saving. Reject grammatical-only
names/aliases and deleted names, aliases, filing/plural equivalents or IDs, even
under another category; explain the rejection without suppressing reading results.

The canonical project deletion history is copied into a bundled asset and loaded
alongside local index data; subsequent shared-blacklist merges update this asset
for future builds. Device-local tombstones remain active immediately. Keep these
scopes distinct: newly shared deletions reach another installed app after its
asset snapshot is rebuilt/reinstalled. No paid API or model inference is added.

Additional authorised UI change: rename # to Main. Offer A–Z/Z–A as well as both
date directions for All, Main and Side. Alphabetical filing skips leading English
function words using the same vocabulary as the addition guard; preserve displayed
titles, stable equal-key ordering and each filter's saved choice.

Acceptance: title field first; no target dropdown; normal index hits do not prompt
or run direct text lookup; No respects both prompts; Yes finds available corrected
passages and offers review; blocked additions explain why and do not write;
valid additions retain anchors and merge using existing rules. Inactive Episodes
must not open a fallback prompt over another tab. Sorting files The Zebra under Z
and On the Origin of Species under O in either direction, for all filters.

Implementation complete; Dart formatting completed. Focused search-flow, addition
policy and sorting tests added/updated, existing two-field browser finders updated.
Tests, analysis, build, app launch and audible/native checks not run for this
change under AGENTS.md. Manual verification and commands are recorded in
outputs/episode-search-and-sorting/README.md. No Git mutations. Phase not applicable.
Suggested commit: `Add index-first episode lookup with reviewed transcript fallback`.

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

## Deletion blacklist and filing headings — 4 November 2026

Persist deleted entries/merged IDs as tombstones and suppress matching exact
category/name/alias headings when new editions or extractor IDs arrive. Registry
replacement/import retains deletion history. Automatically send only deletion
metadata to the authenticated local worker before preparation, preserving an
append-only project ledger for local extraction, enrichment and post-refinement
filtering. Existing tombstones seeded into the ledger by explicit offline sync.
Keep human deletions separate from model rejection. Category-aware exact matching
prevents substring exclusions. Display and alphabetically sort leading The/the
as '<rest>, The/the'; keep source names/evidence and confirmation markers intact.

Acceptance: changed IDs, aliases, merged IDs, restart, import and API renaming
cannot resurrect blacklisted entries; distinct categories/substrings remain;
network request sync is authenticated and omits transcript evidence; filing form
is case-preserving and idempotent. Focused fixtures added; tests/analyzer not run.

## Preserve author graph during entity updates — 4 November 2026

Goal: fix Indexes startup failure after Crossref enrichment: an updated publication
was decoded as a one-entry registry and its valid author IDs could not resolve.
Use immutable entity copies for metadata/variant and blacklist changes; retain full
publication bibliography, ordered author IDs, evidence, review/provenance and
merged IDs. Validate relational references only in the complete registry after
normal author-link reconciliation. Keep strict import/sidecar validation intact.
Acceptance: old descriptive publication adopts a sourced title with multiple
linked authors without a FormatException; linked publications can be blacklisted
without singleton validation; author order/provenance retained; malformed full
registries still rejected. Add focused fixtures. No saved data repair is required
unless examination finds an actually invalid registry. Tests/analyzer remain manual.

## Singular, article-free and descriptive headings — 7 November 2026

Goal: simplify current/future app index entries without losing their occurrence
references, source spellings, review decisions or category boundaries.

Scope/tasks:
- Fold leading The/the and legacy trailing ', The/the' out of filing headings;
  group equivalent entries under the plain spelling when it exists. Preserve all
  source names as aliases, anchor quotations, merged IDs and metadata. Match
  deletion blacklist keys equivalently in Dart and Python so old tombstones work.
- Expand singular/plural merging from organism_group-only to common taxonomy
  names with empty/other common-name subtypes. Prefer the existing singular,
  retain plural aliases and all anchors across episodes. Carry confirmed review
  status; keep rejected/deleted decisions separate. Handle selected irregulars.
  Do not invent a singular when only a plural exists, change scientific genus/
  rank names, or stem author/publication/proper-place names. Generic physical
  place nouns can merge when both forms are present. Persisted plural ownership
  can adopt a returning known singular without changing the canonical ID.
- File recognised descriptive taxonomy/place headings under their noun:
  herbivore animals -> animals, herbivore; marine reptiles -> reptiles, marine;
  early Cretaceous -> Cretaceous, early. Preserve proper adjective capitalisation
  and source names. Keep descriptive entries independent from the broad noun.
  Existing inverted headings are idempotent and combine with equivalent forms.
  Explicit descriptor/head and geological-interval rules avoid guessing that
  Middle East, South Africa, Nile crocodile or publication titles need inversion.
- App registry refresh applies and saves consolidation using existing CAS logic,
  with variant membership preventing refresh/import resurrection. All/episode
  scopes use the same merged entries; occurrence grouping stays unchanged.

Acceptance: Crocodile/Crocodiles with blank subtypes merge with all episode
anchors and plural search; Pacific/The Pacific/Pacific, the display one heading;
source evidence stays literal; descriptive singular/plural pairs merge while
animals and herbivore animals stay independent; DOI-conflicting papers, rejected
entries and formal scientific ranks stay separate; author graph stays valid;
backups/refresh preserve IDs, aliases/reviews and merged references.

Implemented. Modified index_heading.dart, index_models.dart, index_word_forms.dart,
Python index_policy.py, and focused heading/blacklist/word-form policy fixtures.
No files removed. No transcript/audio/source sidecars, live app registry, worker,
external services, API requests or Git operations changed. App refresh performs
the live registry consolidation; existing evidence hashes remain intact.
Dart formatting completed. Focused test/analyzer permission requested; tests and
analysis not run as of this entry. Suggested verification from flutter_app:
`flutter test test/features/indexes/index_word_forms_test.dart test/features/indexes/index_blacklist_test.dart test/features/indexes/index_deletion_test.dart test/features/indexes/publication_refresh_test.dart`
and `flutter analyze`; from project root run `zsh scripts/tests/index_policy_test.zsh`.
Manual: hot reload/restart then Refresh Indexes; check singular aliases, all
cross-episode references, descriptive filing, article-free grouping and deletion
persistence. Record date/tester/environment/results. Unphased task. Suggested
commit: `Consolidate index word forms and file descriptive headings under nouns`.

Verification authorised/completed — 7 November 2026: 25 focused Flutter index
checks passed (word forms, blacklist/deletion persistence, publication/author
refresh), seven offline Python policy tests passed, and flutter analyze reports
no issues. Initial failures exposed two malformed new fixtures (missing edition
anchor data and invalid DOI syntax) and a tombstone-ID regression. Corrected
fixtures to retain strict validators; do not merge deleted records by heading,
so every original deletion ID survives imports/refresh. Cleared five analyzer
findings, including earlier unused PDF test import and null-aware retry-map entry.
No live index registry, worker, source sidecar or external service changed.
App hot reload + Refresh Indexes and native visual review remain for David.

## Transcribed episode filter — 9 November 2026

Goal/scope: add Transcribed alongside All, Main and Side. Use the same
BundledTranscripts.hasEpisode availability rule as listing transcript markers;
include bundled, completed local and connected-library editions without loading
transcript text. Include both main and side episodes. Preserve title/index search
and all sorting choices, defaulting this category to latest first. Refresh visible
results when prepared/library editions change; clear selection if no longer valid.

Implemented in episode controller/browser. Extended sorting/controller coverage
and the existing live transcript-marker widget case. Acceptance: only available
transcripts appear, searches/sorts combine, new/removed editions update immediately,
other filters retain behaviour. Dart formatted; tests/analyzer/builds/launches not
run. See outputs/transcribed-filter/README.md. Unphased; implementation complete,
automated/manual verification pending.

### Transcribed hot-reload correction — 9 November 2026

Reported error: Null is not a subtype of (String) => bool when selecting
Transcribed. The availability callback was added as a constructor-initialised
non-null field; retained pre-change controllers can lack that value after hot
reload. Existing sort maps can also lack the newly added filter key. Changed the
optional injected callback to a nullable backing field with a getter falling back
to BundledTranscripts.hasEpisode, and supplied latest-first when a retained map
has no filter entry. Added a null/default-callback regression fixture.
Dart formatted; tests/analyzer/build/launch not run. A full hot restart (capital R
in flutter run) is recommended to recreate existing controllers after this class
change. Re-run the focused episode_sorting_test.dart and episode_browser_test.dart
commands above. Hot-reload migration itself requires manual acceptance; normal
constructor tests do not prove VM state migration. No Git mutations.
Suggested commit: Guard transcript availability and sort defaults after hot reload.

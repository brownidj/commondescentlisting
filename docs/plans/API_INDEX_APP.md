# Contextual indexes in the app

Authorised 3 November 2026. First estimated four distinct available transcripts
at US$10.87, including the completed Karoo US$2.76; additional estimate US$8.11.
David explicitly approved up to US$12 for the remaining three transcripts.
The estimate scales actual Karoo cost by text length, not a price guarantee.

Implement reusable package extraction with combined budget control and cached
responses; export evidence-bound app entries; preserve Fossils, Places, Papers,
Articles and Authors. Show expandable descriptions, spoken forms, confidence,
normalization caveats, sourced bibliography, links and quotations as in the trial.
No credentials or paid requests in the Flutter client. New references use known
author/date/subject labels, never a fabricated formal title. Publication matching
and external enrichment remain review steps, with sources distinct from quotes.

Match API evidence only to the same episode, edition, passage ID and unchanged
passage text. Resolve current saved timing and offset on Play; never use API times.
Keep existing confirmed/rejected/manual entries and editor/CAS safeguards. Retire
automatic heuristic suggestions from the default view without deleting saved
registries. Preserve detail and anchors through editing and backup/import.

Acceptance: categories unchanged; evidence and metadata survive serialization;
new editions/corrections cannot silently reuse stale contextual hits; trial-style
details render with Open passage/Play; budget and actual usage recorded. Add focused
model/controller/widget tests; leave Flutter tests/analyze/build/native acceptance
for David per project policy. No Git mutations. Store deliverables in outputs/.

Completion: all four transcript indexes compiled into 529 suggestions. Additional recorded API cost US$8.315841; unresolved timeout maximum US$0.8335375; maximum accounted US$9.1493785, below the authorised US$12. David subsequently authorised focused tests and analysis: 21 tests passed, final asset check passed, analyzer clean. No builds/launches/Git mutations. See outputs/indexing-app/RESULTS.md for evidence and native acceptance limitations.

Reference grouping follow-up: show only the first occurrence within each passage; collapse consecutive passage IDs into a first–last range. Group within episode, transcript edition and audio identity only, leaving gaps separate. Apply to inline app entries, the full detail page and the connected trial HTML. Keep source evidence unchanged, show the first quotation, and make Open passage / Play start at the first passage. Add grouping tests and rerun the previously authorised focused tests/analyzer. No new API requests.

Reference grouping completed: first-only duplicate quotations, consecutive ID ranges and separate episode/edition/audio groups. All 19 index tests passed and analyzer clean. See outputs/indexing-app/REFERENCE_RANGES.md.

Word-form follow-up: combine existing singular/plural common organism-group entries under the existing singular heading, retaining both spellings, descriptions and all edition-bound evidence. Deduplicate each passage through the existing occurrence/range rules. Keep genus/species, other categories, ambiguous duplicate headings and conflicting independent review choices separate. Persist merged source IDs so refreshing bundled suggestions cannot resurrect a reviewed plural variant. Preserve raw API output and do not incur API costs. Add focused regressions for bivalve/bivalves, gaps, categories and refresh/review persistence; rerun the authorised index tests and analysis.

Word-form grouping complete. All 24 index tests passed; analyzer clean. See outputs/indexing-app/SINGULAR_PLURAL.md. No API requests or changes to source transcript wording.

Accordion follow-up: opening a contextual index entry closes the previously expanded entry, including after lazy-list disposal or filtering. Apply to the app and cached trial HTML; retain nested publication details. Add widget regression coverage and run the previously authorised index tests and analyzer. No API calls or Git mutations. Done when only one top-level entry stays open and checks pass.

Accordion implemented in app and cached trial HTML. All 25 focused index tests passed and analyzer clean. Native/browser manual acceptance pending; see outputs/indexing-app/ACCORDION.md.

Nearby-reference follow-up: merge successive matching passage IDs when their
difference is strictly less than 30, chaining nearby hits into a first–last range.
A difference of exactly 30 starts a separate range. Preserve first-only duplicate
handling and episode/edition/audio separation, source evidence and first-passage
Play/Open actions. Apply to app and cached trial HTML. Add threshold/chaining
regressions and rerun the previously authorised focused index tests and analysis.
India exists in Places; no dedicated Geologic Time entry currently exists.
No new category or paid extraction is authorised by this follow-up.

Nearby-reference grouping implemented in app and trial HTML. All 26 focused
index tests passed; analyzer clean. Manual visual acceptance pending. See
outputs/indexing-app/NEARBY_REFERENCES.md.

Episode index scope: expose All entries and individual episode choices for every
index category and transcript search. Preserve Fossils, Places, Papers, Articles
and Authors while switching scope. Filter both entry membership and displayed
references; full details and author/publication navigation retain the selected
episode scope. Keep unscoped registry data intact, including stale anchors, and
do not present stale evidence as playable. Accept when shared entries show only
selected-episode references, unrelated entries disappear and All entries restores
them. Add a multi-episode widget regression and run authorised index tests/analyze.

Episode scope implemented. All 27 index tests passed; analyzer clean. Native
manual acceptance pending. See outputs/indexing-app/EPISODE_SCOPE.md.

India and Geologic Time Scale indexing — 3 November 2026: David approved option 1,
a new US$12 combined ceiling, enforced as US$6 per episode. Index current prepared
editions of India (119) and The Geologic Time Scale (12) with existing cached,
evidence-validated extraction. Reuse completed responses, retain unresolved-cost
reserves, stop on errors without speculative retries, preserve categories and
publish both completed indexes into the app asset. Record costs and edition
coverage; run previously authorised focused index tests and analyzer. Existing
registries and review decisions remain intact. No new models or Git mutations.

Both episode indexes completed and exported: India 208 entries, Geologic Time
Scale 126; all five categories in both. Calculated new total US$6.5403695, no
unresolved usage or evidence rejections, within the authorised US$12. Asset now
contains 772 consolidated entries from six transcript indexes. Both current
registered editions verified in the asset. All 27 index tests passed; analyzer
clean. Native checks pending. See outputs/indexing-app/INDIA_GEOLOGIC_TIME.md.

Recategorisation — 4 November 2026: enable Index changes on existing entries and
expose an editable Classification for all categories (e.g. extant species). Keep
IDs, aliases, anchors, details and review metadata. Clear the old classification
when category changes. Fossils currently includes living and extinct organisms;
explain that in the dialog. If an Author is moved to another category, remove its
invalid publication-author links with an explicit review note and dialog notice.
Keep this repair centralized for save/refresh so incoming suggestions cannot
restore invalid relationships. Never edit transcript text or silently alter a
listener's saved entry. Add widget/controller persistence regressions; run the
previously authorised focused index tests/analyzer. No paid requests/Git actions.

Recategorisation implemented with editable Classification, retained evidence,
save/refresh author-link reconciliation and browser category switching. All 32
focused index tests passed; analyzer clean. Native acceptance pending. See
outputs/indexing-app/RECATEGORISATION.md. No listener registry edited automatically.

Taxonomy category — 4 November 2026: rename the visible Fossils category to
Taxonomy. Keep mentions of phyla, classes, orders, families, genera and species
together in one category, including living/extinct organisms. No rank selectors,
classification choices, subindexes or automatic reclassification of stored data.
Keep the existing persisted fossil kind/IDs compatible. Broaden the default local
model label from fossil taxon to taxon; existing organism-group matching stays.
Update category copy and focused selectors; run authorised index tests/analyzer.

Taxonomy label implemented with unchanged persisted kind and one shared category.
All 32 index tests passed; analyzer clean; local script syntax checked. No
classification selectors or reindexing. See outputs/indexing-app/TAXONOMY.md.

Index heading layout — 4 November 2026: move the available-transcripts/contextual-
match count beside Indexes in a wrapping heading row. Preserve count calculations
and filters. No extra controls. Done when formatted; manual narrow/wide inspection
remains pending. No new tests needed for this reversible layout change.

Open passage focus — 4 November 2026: initialise index-focus mode on reader entry
so existing audio-follow cannot override the requested initial passage. Highlight
the requested passage independently from playing/edit selection and keep it in
view while audio continues. Open passage must not seek/start/pause audio. Follow
audio or explicitly playing a passage releases focus. Test idle and active audio
and preserve existing transcript follow behavior. Run focused reader/index checks
and analysis; no native app launch or changes to timings, transcripts or indexes.

Open passage focus implemented. All 42 focused reader/follow/index tests passed;
analyzer clean. Native visual acceptance pending. See outputs/indexing-app/OPEN_PASSAGE.md.

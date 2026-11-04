# External-source enrichment of all existing indexes

David authorised automatic application on 4 November 2026. This supersedes the
earlier trial-only review gates for this rollout. No paid API calls are needed.

Goal: enrich all seven existing episode indexes using cached PBDB, Catalogue of
Life, GeoNames, Macrostrat and Crossref records. Preserve the current categories,
literal transcript evidence, saved deletions and explicit listener edits. Keep
paleocontinents in Places; David confirms Saltville, Virginia.

Apply unique exact identities and source metadata automatically, including
source-backed accepted names where unambiguous. Similarity alone, a higher-rank
fallback, conflicting accepted names or a broad bibliographic topic does not
establish identity. Preserve such entries and list them as hard unresolved.
Authors may inherit metadata only from a matched publication author, not from
co-occurrence. Source lookup failure is a separate deferred/error outcome.

Cache finite serial requests per service, stop on rate limits, retain all raw
responses. Use the small GeoNames city extract in addition to country/region
extracts, not the entire worldwide gazetteer. Record release and attribution.
No transcript/audio changes, model changes, app launch or Git mutation.

Back up all target JSON before mutation, compare before-write hashes, use the app
registry's lock and update package summaries. Export a fresh portable library.
Deduplicate equivalent active headings within a category, retaining aliases,
anchors and variant IDs. Update author links after merging; do not resurrect
rejected/deleted records. Save a machine-readable audit and a searchable HTML
unresolved report with episode/passage evidence. Acceptance is demonstrated by
execution counts, saved hashes and evidence-preservation assertions, not a claim
that database coverage measures indexing accuracy. No new test suite is required;
do not run Flutter analysis/builds/tests for this data task.

## Completed — 4 November 2026

Processed 1296 distinct category/name keys across seven indexed episodes
(eight available edition baselines, including the older bundled Karoo edition).
Applied clear-source enrichment to 222 headings: 137 Taxonomy,
68 Places, 10 Papers, 1 Articles and
6 Authors. This produced 518 entry updates and
27 duplicate merges across the package, assets and saved registry copies.

Gondwana and other recognised paleocontinents remain in Places. Saltville and
Saltville, Virginia are combined under Saltville, Virginia (GeoNames 4784275),
with the earlier wording preserved as an alias. All active copies were checked.

The report lists 922 hard unresolved headings and 152 with stale/incomplete
evidence. Unresolved includes common names, descriptive publication clues,
homonyms, conflicting source taxonomy and source-coverage gaps; these entries
are retained, not declared incorrect. Three malformed taxon-query candidates
are classified as hard unresolved rather than external service failures. No
external-service errors remain in the final outcome counts.

Saved-file/summary checksums, unchanged baseline hashes, original anchors,
previous rejection/deletion decisions, unique active headings and exported
library index/baseline checksums were checked successfully. ZSH syntax and
Git whitespace checks passed. No Flutter tests, analysis, build, launch or Git
mutation. No paid API calls. These integrity checks do not measure extraction
accuracy or independently confirm every database taxonomic opinion.

Use Refresh on the app's Indexes page to reload the saved registry. The report
can be rebuilt without lookups using scripts/indexing/render_external_rollout.zsh.
The enrichment entry point refuses to overwrite an already-applied run, including
in preview mode, preserving this audit. A future rollout needs a separate run
directory/policy update rather than deletion of APPLIED.json.

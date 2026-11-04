# Additional external datasets — evidence-first trials

4 November 2026. After approved PBDB index updates, use Catalogue of Life,
GeoNames and Macrostrat on bounded samples of available transcript indexes.
Preserve source IDs, index/baseline hashes, editions and original quotations.

- Catalogue of Life: resolve latest release once to its immutable dataset key,
  record release metadata, query scientific names and retain accepted/synonym
  status and classification. Exact/fuzzy service results are not confirmation.
- GeoNames: use countryInfo.txt and admin1CodesASCII.txt (small dated downloads,
  CC-BY attribution) for a local country/region lookup. No guessed API username
  or shared demo credentials. Cities, fossil sites, palaeocontinents and geological
  units are outside those extracts; no match is a coverage limit, not rejection.
- Macrostrat v2: named geological units and intervals, with CC-BY source metadata.
  Distinguish intervals from places, preserve Ma bounds and source references.
  Do not silently recategorise or invent a match when a regional unit is absent.

Use a common bounded HTTP cache/review report tool for these three providers.
Explicit --online enables downloads, serial requests, finite timeouts and backoff;
cache-only replay must issue no requests. Errors are distinct from zero matches.
Only PBDB changes already approved are applied; the other datasets' candidate
names and classifications remain staged. No large downloads, model changes,
transcript edits, app/server launches, Git operations or paid APIs.

Acceptance: PBDB backups/CAS/hash verification and duplicate handling; live trials
for each available source with original evidence; offline fixtures for provider
parsing, cache behaviour, stale evidence and ambiguous/no-match handling. Document
any inaccessible service or limited coverage without substituting a different
source silently. Status counts are query outcomes, not accuracy measurements.

## Completed trial — 4 November 2026

Applied nine PBDB-supported scientific-name records (ten source IDs), including
three spelling corrections; merged duplicate Diprotodon headings. Package, bundle,
saved registry and portable library export were updated with backups and verified
hashes. Original transcript and literal evidence were preserved.

Implemented scripts/indexing/lookup_external_datasets.zsh with cache-only replay,
explicit bounded online access and input-hash validation. Catalogue of Life:
five candidate outcomes, one higher-rank partial match and one unresolved query.
GeoNames: eight candidate outcomes and two unresolved queries. Macrostrat: four
candidate outcomes and two unresolved queries. These are query outcomes, not
accuracy measurements; all new source candidates remain staged for review.

Five offline fixtures passed. Live trials completed without errors; cache-only
replay issued zero requests. ZSH syntax and git diff whitespace checks passed.
No paid API calls, native builds, app launches or Git mutations were performed.
Combined review: outputs/external-dataset-trials/marsupials/review.html.

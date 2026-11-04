# Paleobiology Database taxonomy lookup — first trial

4 November 2026. Apply the Crossref approach to Marsupials Taxonomy: optional
cached online lookup, edition-bound literal evidence and a separate review report.
No model change, paid API, transcript rewrite or automatic index update.

## Tasks and acceptance

- ZSH entry point accepts a hash-bound index/baseline/query plan; queries reference
  active Taxonomy entries. Original names/quotes remain distinct from proposed
  scientific-name searches and common-name interpretations.
- Query PBDB data service 1.2 taxa/list using explicit names, readable PBDB field
  vocabulary, bounded results and serial requests. Cache raw dated responses for
  offline replay. Stop uncached requests on rate limits/service unavailability.
- Display original name and passages alongside PBDB taxon/accepted IDs and names,
  rank, attribution, hierarchy, extant indicator, recorded occurrence ages,
  references and source links. Preserve raw responses and service warnings.
- Exact database-name matches are not human confirmation; spelling/synonym and
  common-name mappings require review. No-match means unresolved, not invalid;
  fossil-focused coverage is not a complete taxonomy of all living organisms.
  PBDB age ranges describe its recorded occurrences, not necessarily the full
  taxon's time range. Names and classification can depend on taxonomic opinion.
- Keep all ranks in the existing single Taxonomy index. No new classification
  choices, co-occurrence inference, bulk database download or shared-vocabulary
  promotion. Review before any accepted metadata/name changes in a later step.
- Trial representative exact names, apparent errors, higher taxa, common names
  and a non-taxon control; report counts separately by query outcome, not accuracy.

Done when the bounded trial, review report, offline evidence/cache/error fixtures
and input hashes are recorded. Existing index-check authorisation covers these
focused checks; no Flutter build, server launch or published index mutation.

Sources: https://paleobiodb.org/data1.2/ and the official service implementation
https://github.com/paleobiodb/data_service .

## Implementation evidence

ZSH lookup and separate evidence-first report implemented. Marsupials trial:
16 queries over 13 indexed headings; 11 returned candidate records, 5 unresolved,
0 errors. Three proposed spelling corrections are staged, not applied. All
scientific/common-name interpretations are marked for review. Four offline
fixtures passed, live requests completed and cache-only replay made zero HTTP
requests. Active index hash unchanged. No production promotion or app changes.
See outputs/pbdb-trial/marsupials/README.md for results, limitations and commands.

## Approved application and remaining external datasets

David approved updating the indexes, then similar trials of the other external
sources. Apply the three reviewed spellings and PBDB metadata to direct exact
scientific-name matches, preserving aliases/quotes, merging existing duplicates,
respecting saved deletions and backing up package/summary/bundle/registry. Keep
common-name formalisation hypotheses pending. Refresh the portable library export.

Then trial Catalogue of Life for living taxonomy, GeoNames for modern geography
(using small downloadable gazetteers without an account), and Macrostrat for
geological names/intervals. Cache raw source responses, bind every suggestion to
an index entry and exact transcript evidence, and report unmatched/ambiguous/error
states honestly. These new source results remain separate pending review; no
automatic reclassification or word substitutions. No paid requests or credentials.

## Application completed — 4 November 2026

Approved updates were applied to nine scientific names, covering ten source IDs.
Three headings were corrected with old spellings retained as aliases. Duplicate
Diprotodon entries were merged. Package, bundle and saved registry were updated;
the portable library was re-exported. Backups and before/after hashes are recorded
in outputs/pbdb-trial/marsupials/APPLIED.json. All saved hashes and corrected
headings were verified; transcript text is unchanged. Common-name hypotheses
remain pending review.

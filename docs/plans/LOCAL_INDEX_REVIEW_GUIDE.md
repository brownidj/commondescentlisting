# Reviewing local extraction quality

This phase changes candidate policy, not the GLiNER model. The reviewed shared
vocabulary begins empty. Existing contextual indexes, unreviewed local outputs,
listener edits and deletions are not automatically imported into it.

## Deliberately share confirmed names

Export a registry you have reviewed, using its explicit path. Export goes to a
separate file for inspection; never point it at the listener registry itself.
From the project root:

```zsh
scripts/index_episode_local.zsh --export-vocabulary '/absolute/path/to/registry.json' \
  --output outputs/reviewed-vocabulary.json
```

Only confirmed, non-deleted entries qualify. By default only their canonical names
are shared. Add `--include-aliases` only after checking **all** exported aliases:
old candidates can contain whole quotations and incorrect names. The export
replaces its destination; it does not automatically combine prior vocabulary.
Review names and categories, then deliberately install that file as
`data/reviewed_index_vocabulary.json`. This is the sole production dictionary.
Future matching occurrences still begin as suggestions, never human confirmations.

## What gets retained

Each anchor retains literal quote, full passage, episode GUID, edition and ID.
Its `extraction` list preserves method, original label, model score, half-open
Unicode code-point offsets, extractor version and model revision. Dictionary
revision is the reviewed vocabulary's SHA-256. Multiple detectors on the same
literal anchor retain separate provenance. The app validates spans, preserves
these fields in registry backups/imports/merges, and summarises extraction scores
in the expanded entry's tooltip. Human review status remains separate.

Generic paper/study/research/article mentions live in the edition sidecar's
`unidentified_reference_mentions`, not its five categorized `entries`.
Adjacent cue passages are grouped with context; grouping does not assert they
refer to the same work. Possible model titles without surrounding publication
or attribution cues are also retained as unidentified mentions. Supported model
titles are still provisional, not verified bibliographic identifications.
Pending mentions survive preparation/checkpoint/refinement in `indexing/index.json`;
they are counted in `indexing/summary.json` and the preparation report. They are
not sent as API refinement candidates or displayed as Papers/Articles entries.
A dedicated pending-mention review UI is not part of this phase.

## Independent evaluation

Run extraction into a separate output folder against an existing package. Then:

```zsh
scripts/evaluate_local_index.zsh \
  --index outputs/local-index-quality-phase-1/marsupials/index.json \
  --baseline work/episode-preparation/packages/d873d6f11bc0/67ab163727604fa38db69d940d6fdd88/transcript/baseline.json \
  --output outputs/local-index-quality-phase-1/review-sample.json
```

The seeded random sample includes passages with and without candidates. Read the
passages independently before inspecting suggestions: identify taxa, places,
actual publications and explicitly attributed authors. A person is not necessarily
an author. Mark every candidate `accept` or `reject`; reject duplicates. Add every
missing entity occurrence to `missed_entities` with `category`, `passage_id`,
`name` and a short reason. For a wrong category, reject the original and add a
miss in the correct category. Category keys remain fossil (Taxonomy), place,
paper, article and author. Neighbouring context helps judgement but is not scored.

Only after checking **all** sampled passages, fill `reviewer`, set
`review_complete: true` and run:

```zsh
scripts/evaluate_local_index.zsh \
  --review outputs/local-index-quality-phase-1/review-sample.json \
  --output outputs/local-index-quality-phase-1/evaluation.json
```

Results report accepted occurrences, false candidates and missed entities, with
precision/recall separately for each category; missing denominators are null.
The unit is an entity occurrence within sampled passages, not unique headings or
all words. A sample with no examples of a category cannot establish its quality;
add a separately identified targeted sample if necessary. Human adjudication,
category definitions and sample coverage limit the conclusions. Existing API
outputs are never used as truth labels. The previous 77.8% benchmark measured
agreement with unreviewed API suggestions using different extraction windows; it
is not production accuracy. Synthetic fixtures test code behaviour only.

Transcript edits still invalidate stale anchors without regenerating candidates.
Context-window entity extraction, authorship gating, shared matching semantics,
lookup/caching and incremental reindexing remain later phases.

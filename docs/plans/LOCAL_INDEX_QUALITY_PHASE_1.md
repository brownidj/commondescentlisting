# Local index quality — phase 1

Authorised 4 November 2026. Preserve extraction evidence, separate unidentified
publication mentions, and stop reusing unreviewed candidates as vocabulary.

## Acceptance

- Dictionary matching reads only an explicitly exported, reviewed vocabulary;
  confirmed, non-deleted names are eligible. Aliases require explicit opt-in.
  Listener registries are never discovered or shared automatically.
- Each occurrence retains method, label, model score (distinct from human review),
  exact Unicode code-point span, extractor version and model revision. App
  import/export and merging preserve this evidence; old indexes remain readable.
- Generic paper/study/research/article cues remain unidentified mentions, grouped
  across adjacent passages with literal evidence and context. They never become
  whole-passage publication headings. Model publication titles also require a
  publication/attribution cue in the surrounding passages.
- Pending mentions remain in the edition's index sidecar, survive refinement,
  and are counted in its summary. They are not new index categories or API inputs.
- Provide an independent annotation/evaluation format, with per-category false
  positives and misses. Unreviewed/API suggestions are not an accuracy gold set.

## Verification and limits

Use offline rule fixtures and focused Dart index tests/analyzer under the existing
index-check authorisation. No transcription, paid request, native launch or change
to existing prepared editions. Independent human annotation and production quality
measurement remain separate acceptance work. Context-window entity extraction,
people-versus-authors changes, matching harmonisation and inference caching are
later phases.

## Implementation evidence

Implemented with a separate reviewed vocabulary/export, occurrence provenance,
unidentified mention storage and independent sample evaluator. The app preserves
and validates provenance and shows a compact score summary in the open-entry
tooltip. Five offline rule/evaluator/refinement fixtures and all 47 focused index
tests passed; analyzer clean. Separate Marsupials trial: 1,875 passages, 447
provisional entries, 36 pending reference groups, 13.44 seconds, no API calls.
The 30-passage sample awaits independent annotation; quality is not yet measured.
No existing prepared/published index was replaced. See the review guide and
outputs/local-index-quality-phase-1/README.md for limitations and commands.

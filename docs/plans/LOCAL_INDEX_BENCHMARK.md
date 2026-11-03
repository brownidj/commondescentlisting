# Local transcript indexing benchmark

Authorised 4 November 2026: compare local extraction with the six paid transcript
indexes, without paid requests or changes to the app's published indexes.

Tasks: freeze the six existing source snapshots and API suggestions as a reference;
match names/aliases locally; measure both all-vocabulary reuse and leave-one-episode-
out vocabulary (to expose same-document leakage); run a small local GLiNER model
for unfamiliar entity candidates; preserve five output categories, evidence spans,
passage IDs, episode editions and hashes. Cache model outputs per source/model/
labels/settings so unchanged inputs need no reprocessing. Store dependencies/model
cache under work/local-index-benchmark and deliverables under outputs/local-index-
benchmark. Use a zsh entry point with embedded Python; no new Python entry scripts.

Reference is unreviewed API output, not ground truth. Report entry and passage
agreement by category, missing/extra candidates, local runtime and limitations.
Do not claim precision/recall against scientific truth. Keep papers/articles and
person-versus-author classification provisional; do not invent bibliography or
author links. Write human review samples with source text. Compare literal matches
separately from model-based novel spans; no test-reference labels fed to GLiNER.

Done when all six snapshots have local results, cached reproducible provenance,
a comparison report and a concrete adoption recommendation. User's instruction
to run the proposed benchmark authorises this local benchmark execution; no
Flutter tests, builds, launches, app publication, paid APIs or Git mutations.

Completed: six episodes, 936 episode-specific reference entries. Held-out hybrid
agreement 728/936 (77.8%); same-episode dictionary reuse 905/936 (96.7%). Model
inference 35.35 seconds, excluding setup/download/load; first-run episode work
37.38 seconds. Offline cached rerun has identical statistics; published asset
SHA-256 unchanged. No paid requests. Results support a reviewed local first pass,
not automatic publication; publication identification and category errors remain.
See outputs/local-index-benchmark/RECOMMENDATION.md and REPORT.md. No app changes.

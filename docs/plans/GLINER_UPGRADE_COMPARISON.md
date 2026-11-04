# GLiNER library and larger-model comparison

4 November 2026. Authorised comparisons: (1) GLiNER 0.2.30 with existing
small-v2.1 weights, (2) GLiNER 0.2.30 with large-v2.1 weights.

Keep production default/environment and all published indexes unchanged. Create a
separate environment under work/, pin library/model revisions, download only
required model files, and run the same Marsupials baseline, labels, threshold,
batch size, reviewed vocabulary and extraction policy for each arm. Re-run the
0.2.24/small baseline with the current script for timing comparability. Preserve
index, summary, logs, dependency versions, wall time and process memory readings.
Report category counts and changed occurrence evidence; these are not accuracy
scores. Build a reviewable comparison of differences for independent annotation.

Acceptance: both new-library arms complete with literal edition-bound provenance;
old production version remains installed; no API calls or publication/registration;
o GLiNER2 or external-vocabulary changes. Record timings/memory with platform
limitations and leave human precision/recall unmeasured until annotation. Use
existing offline fixtures and the authorised local trials; no native app build.

## Environment and reproducibility

`work/gliner-upgrade/venv` contains GLiNER 0.2.30. Its
`local_benchmark_dependencies.pth` deliberately references the existing benchmark
environment's dependencies, avoiding a duplicate Torch installation. Upgraded
GLiNER itself is installed in the new environment and takes precedence. This
comparison environment depends on retaining the old benchmark environment;
it is not a standalone deployment environment. `pip check` passed.

Creation steps already carried out (project root):

```zsh
work/local-index-benchmark/venv/bin/python -m venv work/gliner-upgrade/venv
work/gliner-upgrade/venv/bin/python - <<'PY'
from pathlib import Path
import site
source = Path('work/local-index-benchmark/venv/lib/python3.13/site-packages').resolve()
Path(site.getsitepackages()[0], 'local_benchmark_dependencies.pth').write_text(str(source) + '\n')
PY
work/gliner-upgrade/venv/bin/python -m pip install --no-deps gliner==0.2.30
work/gliner-upgrade/venv/bin/python -m pip check
```

Pinned GLiNER weights:
- small: `4e091416cf7c3481db542c2a3d26156916f3a47f` (existing offline cache).
- large: `abd49a1f1ebc12af1be84d06f6848221cf96dcad` (separate cache).

The downloaded encoder/tokenizer metadata revision is recorded in
`work/gliner-upgrade/models.json`. Per-arm dependency versions are in the output
`environment.json`. The runner defaults to Marsupials; optional arguments are
package, edition, output directory and arm selection (`all`, `small`, `large`).
It refuses to overwrite completed arm summaries. Use a fresh output directory to
repeat the experiment. Use the report script after all three arms complete.

```zsh
scripts/indexing/cache_gliner_comparison.zsh
scripts/indexing/compare_gliner_models.zsh
scripts/indexing/report_gliner_comparison.zsh
```

Model selection is opt-in via `index_episode_local.zsh --model` and `--revision`;
`LOCAL_INDEX_PYTHON` and `LOCAL_INDEX_HF_HOME` select comparison runtime/cache.
Production defaults remain 0.2.24 and small-v2.1. No GLiNER2 migration, external
vocabulary addition, threshold tuning or automatic deployment is included here.

## Completed comparison

All three arms completed on the same 1,875 Marsupials passages. 0.2.24/small:
447 entries, 13.30 seconds; 0.2.30/small: 447 entries, 12.79 seconds; 0.2.30/large:
698 entries, 38.32 seconds. The library-only change retained all 974 indexed
occurrences without score changes. Large versus upgraded small: 752 added, 249
removed, 725 retained occurrence spans. Download time excluded.

Post-hoc examples show the large model introducing clear Authors errors such as
“A baby marsupial”, “All right” and “an elephant”. This is not an independent
accuracy evaluation, but argues against promoting the large model automatically.
Keep the small default; production environment and published indexes unchanged.
Five offline fixtures, syntax and report input/hash/span validation passed.
Results, model/dependency metadata and review evidence are in
outputs/gliner-upgrade-comparison/. No paid requests, transcription, GLiNER2,
external vocabulary, Git mutations or native app operations. Human quality
annotation and any production promotion remain separate work.

Decision, 4 November 2026: retain the small model. The large model's dedicated
cache and encoder metadata were deleted at David's request, recovering about
1.78 GB. Temporary range probes were also removed. The comparison downloader is
historical/reproducible, not an active preparation step; do not run it unless an
explicit redownload is wanted. Existing comparison results and runtimes retained.

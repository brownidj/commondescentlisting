#!/bin/zsh
# Manual, offline regression: temporary fixtures only; no media or app launch.
set -euo pipefail
smoke_scripts="${0:A:h:h}"
smoke_project="${smoke_scripts:h}"
export EPISODE_PYTHON="${EPISODE_PYTHON:-${smoke_project}/work/whisperx-trial/venv/bin/python}"
mkdir -p "${smoke_project}/work/episode-pipeline-tests"
smoke_root="$(mktemp -d "${smoke_project}/work/episode-pipeline-tests/run.XXXXXX")"
trap 'rm -rf -- "$smoke_root"' EXIT
export EPISODE_PROJECT="$smoke_root"
export EPISODE_OUTPUTS="${smoke_root}/outputs/episodes/fixture-key"
export EPISODE_WORK="${smoke_root}/work/episode-pipeline/fixture-key"
mkdir -p "${EPISODE_OUTPUTS}/checkpoints" "${EPISODE_WORK}/episode" "${smoke_root}/flutter_app/lib/data" "${smoke_root}/docs/transcripts"
"$EPISODE_PYTHON" - <<'PY'
from pathlib import Path
import hashlib,json,os
p=Path(os.environ['EPISODE_PROJECT']);o=Path(os.environ['EPISODE_OUTPUTS']);w=Path(os.environ['EPISODE_WORK'])
(o/'episode.json').write_text(json.dumps(dict(package_key='fixture-key',guid='fixture-guid',export_stem='fixture',title='Fixture',episode_number='999')))
(w/'episode/audio.opus').write_bytes(b'offline-fixture-audio')
(p/'flutter_app/lib/data/bundled_episode_packages.dart').write_text('''class BundledEpisodePackages {
  static final _repository = EpisodePackageRepository(
    resources: [existingEpisode],
  );
}
''')
(p/'flutter_app/pubspec.yaml').write_text('flutter:\n  assets:\n    - assets/existing/\n')
PY
/bin/zsh "${smoke_scripts}/episode_pipeline/checkpoint.zsh" save encode "${EPISODE_WORK}/episode/audio.opus"
/bin/zsh "${smoke_scripts}/episode_pipeline/checkpoint.zsh" verify encode
print 'tamper' >> "${EPISODE_WORK}/episode/audio.opus"
if /bin/zsh "${smoke_scripts}/episode_pipeline/checkpoint.zsh" verify encode; then
  print -u2 'FAIL: changed stage accepted'; exit 1
fi
print -rn -- 'offline-fixture-audio' > "${EPISODE_WORK}/episode/audio.opus"
mkdir -p "${smoke_root}/flutter_app/assets/episodes"
mv "${EPISODE_WORK}/episode" "${smoke_root}/flutter_app/assets/episodes/fixture-key"
# Simulate interruption just after atomic rename, before publication checkpoint.
/bin/zsh "${smoke_scripts}/episode_pipeline/checkpoint.zsh" verify encode
"$EPISODE_PYTHON" - <<'PY'
from pathlib import Path
import hashlib,json,os
p=Path(os.environ['EPISODE_PROJECT']);o=Path(os.environ['EPISODE_OUTPUTS']);d=p/'flutter_app/assets/episodes/fixture-key'
sha=hashlib.sha256((d/'audio.opus').read_bytes()).hexdigest()
(d/'transcript').mkdir()
for suffix in ['txt','json','srt','vtt']:
    data=b'fixture transcript\n';file='listener.json' if suffix=='json' else 'transcript.'+suffix
    (d/'transcript'/file).write_bytes(data)
    (p/'docs/transcripts'/('fixture.'+suffix)).write_bytes(data)
    (o/('fixture-aligned.'+suffix)).write_bytes(data)
m=dict(episode_guid='fixture-guid',audio=dict(sha256=sha,file='audio.opus',duration_ms=5000,byte_length=21,source_sha256='a'*64),
    transcript=dict(reviewed_file='transcript/baseline.json',alignment_file='transcript/alignment.json',passage_count=1),
    artifacts=[dict(file=f.relative_to(d).as_posix(),byte_length=f.stat().st_size,sha256=hashlib.sha256(f.read_bytes()).hexdigest()) for f in d.rglob('*') if f.is_file()])
(d/'episode.json').write_text(json.dumps(m));(o/'published-manifest.json').write_text(json.dumps(m))
PY
/bin/zsh "${smoke_scripts}/episode_pipeline/checkpoint.zsh" verify-package
/bin/zsh "${smoke_scripts}/episode_pipeline/register_package.zsh"
/bin/zsh "${smoke_scripts}/episode_pipeline/register_package.zsh"
"$EPISODE_PYTHON" - <<'PY'
from pathlib import Path
import hashlib,json,os
p=Path(os.environ['EPISODE_PROJECT']);o=Path(os.environ['EPISODE_OUTPUTS'])
registered=json.loads((o/'registration.json').read_text())['symbol']
legacy='prepared_'+hashlib.sha256(b'fixture-guid').hexdigest()[:16]
f=p/'flutter_app/lib/data/bundled_episode_packages.dart'
f.write_text(f.read_text().replace(registered,legacy))
PY
/bin/zsh "${smoke_scripts}/episode_pipeline/register_package.zsh"
"$EPISODE_PYTHON" - <<'PY'
from pathlib import Path
import os
p=Path(os.environ['EPISODE_PROJECT']);s=(p/'flutter_app/lib/data/bundled_episode_packages.dart').read_text();y=(p/'flutter_app/pubspec.yaml').read_text()
assert s.count('static final preparedEpisode')==1 and 'resources: [existingEpisode, preparedEpisode' in s
assert 'prepared_' not in s
assert y.count('    - assets/episodes/fixture-key/\n')==1
assert y.count('    - assets/episodes/fixture-key/transcript/\n')==1
assert '    - assets/existing/\n' in y
(p/'flutter_app/assets/episodes/fixture-key/audio.opus').write_bytes(b'changed')
PY
if /bin/zsh "${smoke_scripts}/episode_pipeline/checkpoint.zsh" verify-package; then
  print -u2 'FAIL: corrupted published audio accepted'; exit 1
fi
print 'PASS: checkpoint corruption rejection, post-rename recovery, package integrity and idempotent registration.'

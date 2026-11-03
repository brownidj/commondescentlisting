#!/bin/zsh
set -euo pipefail
registration_lock="${EPISODE_PROJECT:?}/work/episode-pipeline/.registration-lock"
mkdir "$registration_lock" 2>/dev/null || { print -u2 "Registration locked: $registration_lock"; exit 2; }
print -r -- "pid=$$ host=$(hostname)" > "${registration_lock}/owner.txt"
trap 'rm -f -- "${registration_lock}/owner.txt"; rmdir -- "$registration_lock"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
"${EPISODE_PYTHON:?}" - <<'PY'
from pathlib import Path
import hashlib,json,os,re
project=Path(os.environ['EPISODE_PROJECT']);outputs=Path(os.environ['EPISODE_OUTPUTS'])
meta=json.loads((outputs/'episode.json').read_text());key=meta['package_key'];asset='assets/episodes/'+key
manifest=json.loads((project/'flutter_app'/asset/'episode.json').read_text()); audio=manifest['audio'];tx=manifest['transcript']
suffix=hashlib.sha256(meta['guid'].encode()).hexdigest()[:16]
symbol='preparedEpisode'+suffix[0].upper()+suffix[1:]
legacy_symbol='prepared_'+suffix
registry=project/'flutter_app/lib/data/bundled_episode_packages.dart';pubspec=project/'flutter_app/pubspec.yaml'
original=registry.read_text(); text=original; yaml=pubspec.read_text()
# Migrate only this GUID's old generated field and its resource-list reference.
text=re.sub(r'\b'+re.escape(legacy_symbol)+r'\b',symbol,text)
# JSON string literals also work in Dart; escape Dart interpolation explicitly.
def literal(value): return json.dumps(value).replace('$',r'\$')
block=f'''  static final {symbol} = EpisodePackageResources(
    key: {literal(key)},
    episodeGuid: {literal(meta['guid'])},
    manifestAsset: {literal(asset+'/episode.json')},
    audio: EpisodeAudioEdition(
      sha256: {literal(audio['sha256'])},
      assetPath: {literal(asset+'/'+audio['file'])},
      codec: EpisodeAudioCodec.opus,
      duration: const Duration(milliseconds: {audio['duration_ms']}),
      byteLength: {audio['byte_length']},
      targetBitrate: 16000,
      sourceSha256: {literal(audio['source_sha256'])},
    ),
    transcript: EpisodeTranscriptAssets(
      reviewedAsset: {literal(asset+'/'+tx['reviewed_file'])},
      alignmentAsset: {literal(asset+'/'+tx['alignment_file'])},
      passageCount: {tx['passage_count']},
    ),
  );

'''
if f'static final {symbol} =' in text:
    actual=re.search(r'  static final '+symbol+r' = EpisodePackageResources\([\s\S]*?\n  \);\n\n',text)
    if not actual or re.sub(r'\s+','',actual.group()).replace("'",'"')!=re.sub(r'\s+','',block).replace("'",'"'): raise SystemExit('Existing generated registration changed; inspect manually.')
else:
    if key in text: raise SystemExit('Package already appears in hand-maintained registry. Inspect before registering twice.')
    marker='  static final _repository = EpisodePackageRepository('
    if text.count(marker)!=1: raise SystemExit('Registry structure changed; no files modified.')
    text=text.replace(marker,block+marker)
resources=re.search(r'resources:\s*\[([^\]]*)\]',text)
if not resources: raise SystemExit('Cannot locate resource list; no files modified.')
items=[s.strip() for s in resources.group(1).split(',') if s.strip()]
if symbol not in items: items.append(symbol)
text=text[:resources.start()]+ 'resources: ['+', '.join(items)+']'+text[resources.end():]
if yaml.count('  assets:\n')!=1: raise SystemExit('Asset declaration changed; no files modified.')
for line in [f'    - {asset}/',f'    - {asset}/transcript/']:
    if line not in yaml.splitlines(): yaml=yaml.replace('  assets:\n','  assets:\n'+line+'\n',1)
# Backups make recovery from a failure between these two atomic replacements
# reviewable. A repeated invocation repairs the missing second half idempotently.
backup=outputs/'registration-backups';backup.mkdir(exist_ok=True)
for path,new in [(registry,text),(pubspec,yaml)]:
    prior=path.read_text()
    if prior!=new:
        saved=backup/path.name
        if not saved.exists(): saved.write_text(prior)
        temp=path.with_name(path.name+'.episode-pipeline.tmp');temp.write_text(new);temp.replace(path)
# Keep local suggestions separate from paid/curated indexes.
local_entries={}
for index_file in (project/'flutter_app/assets/episodes').glob('*/indexing/index.json'):
    for entry in json.loads(index_file.read_text())['entries']:
        local_entries[entry['id']]=entry
local_target=project/'flutter_app/assets/data/local_indexes.json'
local_target.parent.mkdir(parents=True,exist_ok=True)
local_pending=local_target.with_suffix('.pending')
local_pending.write_text(json.dumps(dict(schema_version=1,entries=list(local_entries.values())),indent=2)+'\n')
local_pending.replace(local_target)
(outputs/'registration.json').write_text(json.dumps(dict(episode_guid=meta['guid'],symbol=symbol,files=[str(registry),str(pubspec)],flutter_checks_run=False),indent=2)+'\n')
print('App resource and asset registration saved. Rebuild to include this episode.')
PY

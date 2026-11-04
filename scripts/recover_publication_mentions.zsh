#!/bin/zsh
# Recover attributed references in an existing package without audio/model/API work.
set -euo pipefail
recovery_project="${0:A:h:h}"
exec "${EPISODE_PYTHON:-python3}" - "$recovery_project" "$@" <<'PY_RECOVER'
from pathlib import Path
import argparse,collections,fcntl,json,sys
root=Path(sys.argv[1]);sys.path.insert(0,str(root/'scripts/indexing/lib'))
from index_policy import recover_publications,load_blacklist,apply_blacklist
from enrichment_policy import load,sha,enc,write,active
# Reuse the enrichment pair transaction so the summary never selects an old hash.
source=(root/'scripts/enrich_episode_index.zsh').read_text().split("<<'PY_EPISODE_ENRICH'\n",1)[1].rsplit('\nPY_EPISODE_ENRICH',1)[0]
ns={'__name__':'recovery_helpers'};exec(compile(source,'enrichment-helpers','exec'),ns)
p=argparse.ArgumentParser()
p.add_argument('--package',type=Path,required=True);p.add_argument('--edition',required=True)
p.add_argument('--index',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
a=p.parse_args(sys.argv[2:]);package=a.package.resolve();index=a.index.resolve();summary=index.with_name('summary.json');out=a.output.resolve()
out.mkdir(parents=True,exist_ok=True)
if out==index.parent or out.is_relative_to(package):raise ValueError('Use an output directory outside the package.')
lock=index.with_name(index.name+'.enrichment.lock').open('a');fcntl.lockf(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
ns['recover'](index,summary,out)
manifest=load(package/'episode.json');baseline=(package/manifest['transcript']['reviewed_file']).resolve()
if not baseline.is_relative_to(package):raise ValueError('Unsafe baseline path')
before={path:path.read_bytes() for path in [index,summary]};info=json.loads(before[summary]);base=load(baseline);guid=manifest['episode_guid']
if info['index_sha256']!=sha(before[index]) or info['baseline_sha256']!=sha(baseline.read_bytes()) or info['edition']!=a.edition or info['episode_guid']!=guid or base['episode_guid']!=guid:raise ValueError('Package/index identity mismatch')
document,count=recover_publications(json.loads(before[index]),{(guid,a.edition):{s['id']:s['text'] for s in base['segments']}})
document,suppressed=apply_blacklist(document,load_blacklist(root))
if enc(document)==before[index]:print('No new attributed references or blacklist changes.');sys.exit(0)
attempt=out/'recovery';attempt.mkdir(exist_ok=False)
(attempt/'index-before.json').write_bytes(before[index]);(attempt/'summary-before.json').write_bytes(before[summary])
entries=document['entries'];visible=[e for e in entries if active(e)]
info.update(index_sha256=sha(enc(document)),entries=len(entries),categories=dict(collections.Counter(e['kind'] for e in entries)),active_entries=len(visible),active_categories=dict(collections.Counter(e['kind'] for e in visible)),publication_recovery=dict(recovered=count,blacklisted=suppressed,paid_requests=0))
checkpoint=dict(attempt='recovery',summary=info['publication_recovery'])
write(attempt/'results.json',dict(recovered=count,blacklisted=suppressed,entries=[dict(id=e['id'],name=e['name'],kind=e['kind'],passages=sorted({a['passage_id'] for a in e['anchors']})) for e in visible if e.get('subtype')=='unidentified_publication']))
ns['publish'](index,summary,out,before,{index:enc(document),summary:enc(info)},checkpoint,attempt)
write(out/'results.json',load(attempt/'results.json'))
print(json.dumps(load(out/'results.json'),indent=2))
PY_RECOVER

#!/bin/zsh
# Mark already audited external identities without network or ChatGPT requests.
set -euo pipefail
unset PYTHONOPTIMIZE
confirmation_project="${0:A:h:h:h}"
exec python3 - "$confirmation_project" <<'PY_MARK'
from pathlib import Path
import fcntl,json,sys
root=Path(sys.argv[1]);sys.path.insert(0,str(root/'scripts/indexing/lib'))
from enrichment_policy import load,sha,enc,write,canon,active,confirmation_evidence
out=root/'outputs/preparation-enrichment-order/confirmation-backfill';out.mkdir(parents=True,exist_ok=True)
if (out/'APPLIED.json').exists():raise SystemExit('Confirmation backfill already applied; inspect its audit before repeating.')
rollout=root/'outputs/external-index-rollout';rows=load(rollout/'results.json')['results']
rows=[r for r in rows if r['status']=='applied' and r.get('matched')]
paths=[Path(f['path']) for f in load(rollout/'APPLIED.json')['files'] if Path(f['path']).name!='summary.json']
packages={};baselines={};summaries=[]
for p in (root/'flutter_app/assets/episodes').glob('*/episode.json'):
 m=load(p);packages[(m['episode_guid'],m['audio']['identity'])]=p.parent
for guid,item in load(root/'work/episode-preparation/library.json').items():
 packages[(guid,item['edition'])]=root/item['package']
 if item.get('index_directory'):paths.append(root/item['index_directory']/'index.json')
for (guid,edition),package in packages.items():
 m=load(package/'episode.json');baselines[(guid,edition)]={r['id']:r['text'] for r in load(package/m['transcript']['reviewed_file'])['segments']}
paths=list(dict.fromkeys(p for p in paths if p.exists()))
for p in paths:
 if p.name=='index.json' and p.with_name('summary.json').exists():summaries.append(p.with_name('summary.json'))
registry=next((p for p in paths if p.name=='registry.json'),None)
lock=Path(str(registry)+'.lock').open('a') if registry else (out/'backfill.lock').open('a');fcntl.lockf(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
before={p:p.read_bytes() for p in paths+summaries};after={};marked=[];skipped=[]
for p in paths:
 d=json.loads(before[p]);count=0
 for e in d['entries']:
  if not active(e):continue
  ids={e['id'],*e.get('variant_ids',[])}
  matches=[r for r in rows if ids.intersection(r['source_ids']) and canon(e['name'])==canon(r.get('target_name',r['name'])) and e['kind']==r.get('target_kind',r['kind'])]
  if not matches:continue
  proofs=[a for r in matches for a in r['anchors'] if a in e['anchors'] and baselines.get((a['guid'],a['edition']),{}).get(a['passage_id'])==a['passage_text']]
  if not proofs:skipped.append(dict(path=str(p),id=e['id'],reason='No unchanged, current-edition audit evidence'));continue
  sources=sorted({m['provider'] for r in matches for m in r['matched']})
  details=e.get('details') or {};e['details']=details
  details['external_confirmation']=json.dumps(dict(status='confirmed',name=e['name'],kind=e['kind'],sources=sources,evidence=confirmation_evidence(dict(anchors=proofs[:1]))),ensure_ascii=False)
  count+=1
 if count:after[p]=enc(d);marked.append(dict(path=str(p),entries=count))
for p in summaries:
 source=p.with_name('index.json')
 if source not in after:continue
 d=json.loads(before[p]);d['index_sha256']=sha(after[source]);after[p]=enc(d)
backup=out/'before';backup.mkdir(exist_ok=False)
for i,(p,b) in enumerate(before.items()):(backup/(str(i)+'-'+p.name)).write_bytes(b)
if any(p.read_bytes()!=b for p,b in before.items()):raise SystemExit('Concurrent index edit; nothing written.')
for p,b in after.items():
 tmp=p.with_name(p.name+'.confirmation-pending');tmp.write_bytes(b);tmp.replace(p)
write(out/'APPLIED.json',dict(marked=marked,skipped=skipped,files=[dict(path=str(p),before_sha256=sha(before[p]),after_sha256=sha(b)) for p,b in after.items()],paid_requests=0,network_requests=0,transcripts_modified=False))
print('Recorded existing confirmations:',marked,'skipped',len(skipped))
PY_MARK

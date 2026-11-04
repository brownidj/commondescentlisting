#!/bin/zsh
# Apply unambiguous external identities; retain uncertain entries for review.
set -euo pipefail
enrichment_project="${0:A:h:h:h}"
exec python3 - "$enrichment_project" "$@" <<'PY_ENRICH'
from pathlib import Path
import argparse,collections,concurrent.futures,copy,datetime,fcntl,hashlib,html,io,json,re,sys,threading,time,unicodedata,urllib.request,urllib.parse,urllib.error,zipfile
root=Path(sys.argv[1]);parser=argparse.ArgumentParser()
parser.add_argument('--online',action='store_true');parser.add_argument('--apply',action='store_true')
args=parser.parse_args(sys.argv[2:])
sys.path.insert(0,str(root/'scripts/indexing/lib'))
from enrichment_policy import EnrichmentPolicy,apply_document,reconcile_authors,load,sha,enc,write,canon,unique,active
out=root/'outputs/external-index-rollout';out.mkdir(parents=True,exist_ok=True)
if (out/'APPLIED.json').exists():raise SystemExit('Rollout already applied; preserve this audit. Use render_external_rollout.zsh to rebuild the saved report.')
registry=Path('/Users/david/Library/Containers/com.example.commonDescentListing/Data/Library/Application Support/com.example.commonDescentListing/indexes/registry.json')
paths=[root/'flutter_app/assets/data/contextual_indexes.json',root/'flutter_app/assets/data/local_indexes.json']
packages={};baselines={};titles={};summaries=[]
for manifest in (root/'flutter_app/assets/episodes').glob('*/episode.json'):
 m=load(manifest);package=manifest.parent;guid=m['episode_guid'];edition=m['audio']['identity']
 packages[(guid,edition)]=package
for guid,item in load(root/'work/episode-preparation/library.json').items():packages[(guid,item['edition'])]=root/item['package']
for (guid,edition),package in packages.items():
 m=load(package/'episode.json');base=package/m['transcript']['reviewed_file'];baselines[(guid,edition)]={s['id']:s['text'] for s in load(base)['segments']};titles[guid]=m['metadata']['title']
 if (package/'indexing/index.json').exists():paths.append(package/'indexing/index.json');summaries.append(package/'indexing/summary.json')
if registry.exists():paths.append(registry)
paths=list(dict.fromkeys(paths));before={p:p.read_bytes() for p in paths+summaries};docs={p:json.loads(before[p]) for p in paths}
entities={};invalid=[]
for p,d in docs.items():
 for e in d['entries']:
  if not active(e):continue
  key=(e['kind'],canon(e['name']))
  entities.setdefault(key,[]).append(e)
policy=EnrichmentPolicy(root,baselines,args.online)
resolve=policy.resolve;valid_anchors=policy.valid_anchors;sent=policy.sent;cache_hits=policy.cache_hits
items=sorted(entities.items());results=[]
print('Resolving',len(items),'distinct category/name keys across',len(packages),'episode editions',flush=True)
with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
 futures={pool.submit(resolve,key,group):key for key,group in items}
 for f in concurrent.futures.as_completed(futures):
  try:row=f.result()
  except Exception as exc:
   key=futures[f];print('LOOKUP ERROR',key,type(exc).__name__,str(exc),flush=True)
   row=dict(kind=key[0],name=entities[key][0]['name'],source_ids=[e['id'] for e in entities[key]],anchors=[],matched=[],errors=[type(exc).__name__+': '+str(exc)],status='lookup_error',reason='Extractor could not process this entry')
  results.append(row)
  with (out/'progress.jsonl').open('a') as stream:stream.write(json.dumps({k:v for k,v in row.items() if k!='anchors'},ensure_ascii=False)+'\n')
  if len(results)%25==0:print('Processed',len(results),'of',len(items),dict(collections.Counter(r['status'] for r in results)),'requests',dict(sent),flush=True)
reconcile_authors(results)
write(out/'results.json',dict(schema_version=1,results=results,requests_sent=dict(sent),cache_hits=dict(cache_hits),paid_api_calls=0,catalogue_of_life_release=316595,source_files=[dict(path=str(p),sha256=sha(b)) for p,b in before.items()]))
# Snapshot compare-and-swap plus app-compatible advisory lock. No network while locked.
if args.apply:
 lock=Path(str(registry)+'.lock').open('a');fcntl.lockf(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
 if any(p.read_bytes()!=b for p,b in before.items()):raise SystemExit('Input changed during lookup. No files changed; rerun using the cache.')
 changes=[];merges=[]
 for p,d in list(docs.items()):
  docs[p],changed,merged=apply_document(d,results,policy)
  changes.extend(dict(c,path=str(p)) for c in changed);merges.extend(dict(c,path=str(p)) for c in merged)
 new={p:enc(d) for p,d in docs.items()}
 for p in summaries:
  d=json.loads(before[p]);index=p.parent/'index.json';es=[e for e in docs[index]['entries'] if active(e)]
  d.update(index_sha256=sha(new[index]),active_entries=len(es),active_categories=dict(collections.Counter(e['kind'] for e in es)),external_enrichment=dict(date='2026-11-04',authorised_by='David',report='outputs/external-index-rollout/results.json'));new[p]=enc(d)
 backup=out/'before-apply';backup.mkdir(exist_ok=False)
 for i,(p,b) in enumerate(before.items()):(backup/(str(i)+'-'+p.name)).write_bytes(b)
 # Preserve every existing anchor and rejected/deleted decision; merging only adds anchors.
 for p,d in docs.items():
  old={e['id']:e for e in json.loads(before[p])['entries']}
  for e in d['entries']:
   assert all(a in e['anchors'] for a in old[e['id']]['anchors'])
   if not active(old[e['id']]):assert e==old[e['id']],('Prior saved decision changed',e['id'])
 assert all(p.read_bytes()==b for p,b in before.items())
 for p,b in new.items():
  temp=p.with_name(p.name+'.enrichment-pending');temp.write_bytes(b);temp.replace(p)
 write(out/'APPLIED.json',dict(changes=changes,merges=merges,files=[dict(path=str(p),before_sha256=sha(before[p]),after_sha256=sha(b)) for p,b in new.items()],transcript_modified=False,paid_api_calls=0))
import subprocess
subprocess.run([str(root/'scripts/indexing/render_external_rollout.zsh')],check=True)
print('COMPLETE: see',out/'APPLIED.json',flush=True)
PY_ENRICH

#!/bin/zsh
# Per-episode, resumable external-source enrichment. No recognition or paid API.
set -euo pipefail
unset PYTHONOPTIMIZE
enrich_project="${0:A:h:h}"
exec "${EPISODE_PYTHON:-python3}" -u - "$enrich_project" "$@" <<'PY_EPISODE_ENRICH'
from pathlib import Path
import argparse,collections,fcntl,hashlib,html,json,os,signal,sys,time,uuid
root=Path(sys.argv[1]);sys.path.insert(0,str(root/'scripts/indexing/lib'))
from enrichment_policy import EnrichmentPolicy,apply_document,reconcile_authors,load,sha,enc,write,canon,active,externally_confirmed

def fingerprint(root):
 files=[root/'scripts/enrich_episode_index.zsh',root/'scripts/indexing/lib/enrichment_policy.py',root/'scripts/indexing/enrichment_sources.json',*[root/'scripts/indexing'/n for n in ['lookup_pbdb.zsh','lookup_external_datasets.zsh','lookup_crossref.zsh']]]
 return {str(p.relative_to(root)):sha(p.read_bytes()) for p in files}

def recover(index,summary,out):
 journal=out/'transaction.json'
 if not journal.exists():return
 tx=load(journal)
 if tx['index_path']!=str(index) or tx['summary_path']!=str(summary):raise ValueError('Pending transaction belongs to another sidecar')
 for target,key in [(index,'index'),(summary,'summary')]:
  b=(out/tx[key+'_file']).read_bytes()
  if sha(b)!=tx[key+'_after']:raise ValueError('Recovery artifact checksum mismatch')
  current=sha(target.read_bytes())
  if current not in [tx[key+'_before'],tx[key+'_after']]:raise ValueError('Concurrent sidecar edit; recovery refused')
 # Journal is durable before either target changes; finish the same prepared pair.
 for target,key in [(index,'index'),(summary,'summary')]:
  b=(out/tx[key+'_file']).read_bytes();temp=target.with_name(target.name+'.enrichment-pending');temp.write_bytes(b);temp.replace(target)
 write(out/'checkpoint.json',tx['checkpoint']);write(out/'results.json',load(out/tx['checkpoint']['attempt']/'results.json'));journal.unlink()

def publish(index,summary,out,before,after,checkpoint,attempt):
 tx=dict(index_path=str(index),summary_path=str(summary),checkpoint=checkpoint)
 for target,key in [(index,'index'),(summary,'summary')]:
  if target.read_bytes()!=before[target]:raise ValueError('Sidecar changed during lookup; no overwrite')
  relative=str((attempt/(key+'-after.json')).relative_to(out));(out/relative).write_bytes(after[target])
  tx.update({key+'_file':relative,key+'_before':sha(before[target]),key+'_after':sha(after[target])})
 write(out/'transaction.json',tx)
 try:
  for target in [index,summary]:
   temp=target.with_name(target.name+'.enrichment-pending');temp.write_bytes(after[target]);temp.replace(target)
  write(out/'checkpoint.json',checkpoint);(out/'transaction.json').unlink()
 except BaseException:
  # Signal cancellation between the pair restores our own writes only.
  for target in [index,summary]:
   if target.read_bytes()==after[target]:
    tmp=target.with_name(target.name+'.enrichment-pending');tmp.write_bytes(before[target]);tmp.replace(target)
  (out/'transaction.json').unlink(missing_ok=True)
  raise

def render(out,report):
 esc=lambda x:html.escape(str(x));cards=[]
 for row in report['results']:
  if row['status']=='applied' and not row['errors']:continue
  refs=row.get('source_anchors',row['anchors'])
  cards.append('<details><summary>'+esc(row['name'])+' · '+esc({'fossil':'Taxonomy','place':'Places','paper':'Papers','article':'Articles','author':'Authors'}.get(row['kind'],row['kind']))+' · '+esc(row['status'])+'</summary><p>'+esc(row['reason'])+'</p><p>'+esc('; '.join(row['errors']))+'</p>'+''.join('<blockquote>Passage '+esc(a.get('passage_id','not recorded'))+' — '+esc(a.get('passage_text',a.get('quote','')))+'</blockquote>' for a in refs)+'</details>')
 (out/'review.html').write_text('<!doctype html><meta charset="utf-8"><title>Episode enrichment report</title><style>body{font:16px system-ui;max-width:1000px;margin:30px auto}details{padding:12px;border:1px solid #ccc;margin:8px}summary{cursor:pointer}blockquote{border-left:3px solid teal;padding:10px}</style><h1>'+esc(report['title'])+' — external enrichment</h1><p>'+esc(report['summary'])+'</p>'+''.join(cards))
 (out/'README.md').write_text('# '+report['title']+' — external enrichment\n\n'+json.dumps(report['summary'],indent=2)+'\n\nReview unresolved identities and stale evidence in review.html. Lookup failures retain the usable index and can be retried without transcription or ChatGPT.\n')

def main(argv=None):
 parser=argparse.ArgumentParser(description='Enrich one index sidecar; default uses cached and bounded online sources.')
 for key in ['package','index','output']:parser.add_argument('--'+key,type=Path,required=True)
 parser.add_argument('--edition',required=True);parser.add_argument('--offline',action='store_true');parser.add_argument('--retry',action='store_true')
 a=parser.parse_args(sys.argv[2:] if argv is None else argv);package=a.package.resolve();index=a.index.resolve();summary=index.with_name('summary.json');out=a.output.resolve();out.mkdir(parents=True,exist_ok=True)
 if out==index.parent or out.is_relative_to(package/'transcript'):raise ValueError('Use a separate enrichment output directory')
 lock=index.with_name(index.name+'.enrichment.lock').open('a');fcntl.lockf(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
 recover(index,summary,out)
 manifest=load(package/'episode.json');baseline=(package/manifest['transcript']['reviewed_file']).resolve()
 if not baseline.is_relative_to(package):raise ValueError('Unsafe transcript path')
 before={p:p.read_bytes() for p in [index,summary]};doc=json.loads(before[index]);info=json.loads(before[summary]);base=load(baseline);guid=manifest['episode_guid']
 if base['episode_guid']!=guid or info['episode_guid']!=guid or info['edition']!=a.edition or info['index_sha256']!=sha(before[index]):raise ValueError('Index summary, episode, edition or input hash mismatch')
 if info.get('baseline_sha256') and info['baseline_sha256']!=sha(baseline.read_bytes()):raise ValueError('Baseline changed; regenerate the sidecar before enrichment')
 identity=dict(episode_guid=guid,edition=a.edition,baseline_sha256=sha(baseline.read_bytes()),manifest_sha256=sha((package/'episode.json').read_bytes()),policy=fingerprint(root))
 checkpoint=out/'checkpoint.json'
 if checkpoint.exists() and not a.retry:
  saved=load(checkpoint)
  if saved['identity']==identity and saved['output_index_sha256']==sha(before[index]) and saved['output_summary_sha256']==sha(before[summary]):
   write(out/'summary.json',saved['summary']);write(out/'results.json',load(out/saved['attempt']/'results.json'));print('ENRICH_PROGRESS 1 1',flush=True);print('Enrichment checkpoint reused:',saved['summary']['state'],flush=True);return saved['summary']
 attempt=out/'attempts'/uuid.uuid4().hex;attempt.mkdir(parents=True)
 (attempt/'index-before.json').write_bytes(before[index]);(attempt/'summary-before.json').write_bytes(before[summary])
 policy=EnrichmentPolicy(root,{(guid,a.edition):{s['id']:s['text'] for s in base['segments']}},not a.offline)
 groups=collections.defaultdict(list)
 for e in doc['entries']:
  if active(e):groups[(e['kind'],canon(e['name']))].append(e)
 rows=[];total=len(groups);started=time.monotonic()
 for done,(key,group) in enumerate(sorted(groups.items()),1):
  token=sha(enc(dict(identity=identity,entries=group)))
  cached=out/'resolutions'/(token+'.json')
  if cached.exists() and not load(cached).get('errors'):row=load(cached)
  else:
   try:row=policy.resolve(key,group)
   except Exception as exc:row=dict(kind=key[0],name=group[0]['name'],anchors=[],source_anchors=[a for e in group for a in e['anchors']],source_ids=[e['id'] for e in group],matched=[],errors=[str(exc)],status='lookup_error',reason='Source lookup unavailable; retained original entry')
   write(cached,row)
  rows.append(row);write(out/'progress.json',dict(completed=done,total=total,fraction=done/max(1,total),name=row['name']))
  print('ENRICH_PROGRESS',done,total,flush=True)
 reconcile_authors(rows);updated,changes,merges=apply_document(doc,rows,policy)
 for old,new in zip(doc['entries'],updated['entries']):
  if not active(old) and old!=new:raise ValueError('Saved deletion/rejection changed')
  if any(a not in new['anchors'] for a in old['anchors']):raise ValueError('Original evidence removed')
 outcomes=dict(collections.Counter(r['status'] for r in rows));warnings=sorted(set(policy.place_errors+[error for row in rows for error in row['errors']]))
 confirmed=sum(active(e) and externally_confirmed(e) for e in updated['entries'])
 result=dict(confirmed_external=confirmed,state='partial' if warnings else 'completed',entries=total,enriched=outcomes.get('applied',0),unresolved=outcomes.get('hard_unresolved',0),stale=outcomes.get('stale_evidence',0),lookup_errors=outcomes.get('lookup_error',0),duplicates_merged=len(merges),warnings=warnings,offline=a.offline,paid_api_calls=0,requests_sent=dict(policy.sent),cache_hits=dict(policy.cache_hits),seconds=round(time.monotonic()-started,2),report=str(out/'review.html'))
 payload=enc(updated);es=[e for e in updated['entries'] if active(e)]
 info.update(index_sha256=sha(payload),entries=len(updated['entries']),categories=dict(collections.Counter(e['kind'] for e in updated['entries'])),active_entries=len(es),active_categories=dict(collections.Counter(e['kind'] for e in es)),external_enrichment=result)
 after={index:payload,summary:enc(info)};context=dict(identity=identity,input_index_sha256=sha(before[index]),input_summary_sha256=sha(before[summary]),output_index_sha256=sha(payload),output_summary_sha256=sha(after[summary]),summary=result,attempt=str(attempt.relative_to(out)))
 report=dict(schema_version=1,title=manifest['metadata']['title'],episode_guid=guid,edition=a.edition,summary=result,identity=identity,input_index_sha256=sha(before[index]),output_index_sha256=sha(payload),results=rows,changes=changes,merges=merges)
 write(attempt/'results.json',report);render(out,report)
 if sha(baseline.read_bytes())!=identity['baseline_sha256'] or sha((package/'episode.json').read_bytes())!=identity['manifest_sha256'] or fingerprint(root)!=identity['policy']:raise ValueError('Package or policy changed during enrichment')
 publish(index,summary,out,before,after,context,attempt)
 write(out/'results.json',report);write(out/'summary.json',result)
 print('ENRICH_PROGRESS',total,total,flush=True)
 print('External enrichment:',result['state'],'enriched',result['enriched'],'unresolved',result['unresolved'],'stale',result['stale'],'source warnings',len(warnings),flush=True)
 return result

if __name__=='__main__':
 def interrupted(signum,frame):raise KeyboardInterrupt('Enrichment cancelled; usable index retained')
 signal.signal(signal.SIGTERM,interrupted);signal.signal(signal.SIGINT,interrupted)
 try:main()
 except KeyboardInterrupt:sys.exit(130)
PY_EPISODE_ENRICH

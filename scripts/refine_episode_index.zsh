#!/bin/zsh
# One bounded contextual review after local indexing; never retranscribes audio.
set -euo pipefail
unset PYTHONOPTIMIZE
refine_project="${0:A:h:h}"
exec "${EPISODE_PYTHON:-${refine_project}/work/whisperx-trial/venv/bin/python}" -u - "$refine_project" "$@" <<'PY_REFINE'
from pathlib import Path
import argparse,copy,collections,hashlib,json,os,stat,sys,urllib.request,urllib.error,http.client,time,uuid,fcntl

sys.path.insert(0,str(Path(sys.argv[1])/'scripts/indexing/lib'))
from enrichment_policy import externally_confirmed,metadata_snapshot,confirmation_evidence
from index_policy import recover_publications,apply_blacklist,load_blacklist
from refinement_transport import tls_context,connection_problem

KINDS={'Taxonomy':'fossil','Places':'place','Papers':'paper','Articles':'article','Authors':'author'}
LABELS={v:k for k,v in KINDS.items()}
META=['name','kind','review','aliases','subtype','year','publication','doi','url','link_verified','author_ids','note']
def encoded(value):return (json.dumps(value,ensure_ascii=False,indent=2)+'\n').encode()
def sha(data):return hashlib.sha256(data).hexdigest()
def load(p):return json.loads(p.read_text())
def atomic(p,value):
 p.parent.mkdir(parents=True,exist_ok=True);tmp=p.with_name(p.name+'.pending');tmp.write_bytes(encoded(value));tmp.replace(p)
def credential(project):
 p=project/'work/indexing-trial/openai-api-key'
 if not p.is_file():raise ValueError('Configure the OpenAI key with scripts/configure_indexing_key.zsh, or turn off ChatGPT refinement.')
 if stat.S_IMODE(p.stat().st_mode)&0o077:raise ValueError('OpenAI credential file must have private permissions (chmod 600).')
 key=p.read_text().strip()
 if not key:raise ValueError('OpenAI credential file is empty.')
 return key

def api_review_current(entry,model):
 try:marker=json.loads((entry.get('details') or {}).get('refinement_review','{}'))
 except (ValueError,TypeError):return False
 return (isinstance(marker,dict) and marker.get('model')==model and marker.get('metadata')==metadata_snapshot(entry)
         and bool(marker.get('evidence')) and all(a in confirmation_evidence(entry) for a in marker['evidence']))

def evidence_context(candidates,passages):
 for c in candidates:
  allowed=set(c['passages'])
  if any(k in ['Authors','Papers','Articles'] for k in c['categories']):
   allowed.update(str(int(pid)+d) for pid in c['passages'] for d in range(-2,3) if str(int(pid)+d) in passages)
  c['evidence_passages']=sorted(allowed,key=int)
 return candidates

def prepare_request(index,baseline,edition,title,config):
 index,_=recover_publications(index,{(baseline['episode_guid'],edition):{p['id']:p['text'] for p in baseline['segments']}})
 cues={p['id']:p['text'] for p in baseline['segments']}
 if len({e['id'] for e in index['entries']})!=len(index['entries']):raise ValueError('Duplicate index IDs.')
 if len(cues)!=len(baseline['segments']):raise ValueError('Duplicate passage IDs.')
 candidates=[];mapping={};contexts={}
 for e in index['entries']:
  anchors=e['anchors']
  for a in anchors:
   if a['guid']!=baseline['episode_guid'] or a['edition']!=edition or a['passage_text']!=cues.get(a['passage_id']) or a['quote'] not in a['passage_text']:raise ValueError('Index evidence does not match this transcript edition.')
  if e.get('deleted') or e['review']!='suggested' or not anchors or externally_confirmed(e) or api_review_current(e,config['model']):continue
  selected=sorted(anchors,key=lambda a:(e['name'].casefold() not in a['quote'].casefold(),a['passage_id']))
  pids=list(dict.fromkeys(a['passage_id'] for a in selected))[:3]
  cid=len(candidates)+1;mapping[cid]=e['id']
  candidates.append(dict(id=cid,name=e['name'],categories=[LABELS[e['kind']]],passages=[str(p) for p in pids],aliases=e['aliases'][:2]))
  for pid in pids:
   contexts[str(pid)]=cues[pid]
   if e['kind'] in ['author','paper','article']:
    for near in range(pid-2,pid+3):
     if near in cues:contexts[str(near)]=cues[near]
 evidence_context(candidates,contexts)
 payload=dict(episode=title,candidates=candidates,passages=contexts)
 request=dict(model=config['model'],service_tier='default',reasoning={'effort':'none'},store=False,instructions=config['instructions'],input=json.dumps(payload,ensure_ascii=False,separators=(',',':')),text={'format':{'type':'json_schema','name':'index_review','strict':True,'schema':config['schema']}},max_output_tokens=config['max_output_tokens'])
 # UTF-8 bytes plus framing allowance intentionally overestimates input tokens.
 ceiling=((len(encoded(request))+4096)*config['input_per_million']*1.25+config['max_output_tokens']*config['output_per_million'])/1e6
 return request,candidates,mapping,ceiling

def validate(data,candidates):
 if not isinstance(data,dict) or set(data)!={'reviews'} or not isinstance(data['reviews'],list):raise ValueError('Invalid review document.')
 expected={c['id']:c for c in candidates};rows=data['reviews'];seen=set();required={'id','action','category','normalized_name','merge_into','confidence','reason','evidence_passage_ids'}
 for r in rows:
  if not isinstance(r,dict) or set(r)!=required or type(r['id']) is not int or r['id'] not in expected or r['id'] in seen:raise ValueError('Missing, unexpected or duplicate candidate IDs.')
  seen.add(r['id'])
  if r['action'] not in ['keep','recategorise','merge','reject','uncertain'] or r['category'] not in [*KINDS,None] or r['confidence'] not in ['high','medium','low']:raise ValueError('Invalid review choice.')
  if not isinstance(r['reason'],str) or not 0<len(r['reason'])<=1000:raise ValueError('Invalid review reason.')
  n=r['normalized_name']
  if n is not None and (not isinstance(n,str) or not n.strip() or len(n)>1000):raise ValueError('Invalid normalized name.')
  evidence=r['evidence_passage_ids']
  if not isinstance(evidence,list) or not evidence or any(type(p) is not int or str(p) not in expected[r['id']].get('evidence_passages',expected[r['id']]['passages']) for p in evidence):raise ValueError('Unsupported evidence passage.')
  if r['action'] in ['keep','recategorise','merge'] and r['category'] is None:raise ValueError('Missing target category.')
  target=r['merge_into']
  if r['action']=='merge':
   if type(target) is not int or target not in expected or target==r['id']:raise ValueError('Invalid merge target.')
  elif target is not None:raise ValueError('Unexpected merge target.')
 if seen!=set(expected):raise ValueError('Review coverage incomplete.')
 byid={r['id']:r for r in rows}
 for r in rows:
  seen={r['id']};target=r['merge_into']
  while target is not None:
   if target in seen:raise ValueError('Merge cycle.')
   seen.add(target);t=byid[target]
   if t['action'] in ['reject','uncertain'] or t['category']!=r['category']:raise ValueError('Conflicting merge target.')
   target=t['merge_into']
 return byid

def recover_reviews(data,candidates):
 if not isinstance(data,dict) or set(data)!={'reviews'} or not isinstance(data['reviews'],list):raise ValueError('Invalid review document.')
 expected={c['id']:c for c in candidates};accepted={};issues={};seen=set()
 def held(cid):return dict(id=cid,action='uncertain',category=None,normalized_name=None,merge_into=None,confidence='low',reason='No validated API decision; retained for review.',evidence_passage_ids=[int(expected[cid]['passages'][0])])
 for row in data['reviews']:
  cid=row.get('id') if isinstance(row,dict) else None
  if type(cid) is not int or cid not in expected or cid in seen:raise ValueError('Unknown or duplicate API candidate ID; response retained without applying.')
  seen.add(cid)
  probe=copy.deepcopy(row)
  if probe.get('action')=='merge':probe.update(action='keep',merge_into=None)
  try:validate(dict(reviews=[probe]),[expected[cid]])
  except ValueError as error:issues[cid]=str(error);continue
  accepted[cid]=row
 missing=set(expected)-seen
 rows={cid:accepted.get(cid,held(cid)) for cid in expected}
 try:valid=validate(dict(reviews=list(rows.values())),candidates)
 except ValueError:
  # A bad or missing merge target must not discard independent valid decisions.
  for cid,row in list(rows.items()):
   if row['action']=='merge':rows[cid]=held(cid);issues[cid]='Merge target/cycle could not be validated';accepted.pop(cid,None)
  valid=validate(dict(reviews=list(rows.values())),candidates)
 return valid,dict(api_rows_received=len(seen),validated_candidates=len(accepted),missing_candidates=len(missing),invalid_candidates=len(issues),missing_ids=sorted(missing),invalid_rows=[dict(id=cid,reason=reason) for cid,reason in sorted(issues.items())])

def unique(values):return list({json.dumps(v,sort_keys=True,ensure_ascii=False):v for v in values}.values())
def metadata_history(details,old):
 try:prior=json.loads(details.get('refinement_source','{}'))
 except (ValueError,TypeError):prior={}
 rows=prior if isinstance(prior,list) else [prior]
 rows=unique([v for v in rows if isinstance(v,dict) and set(v)==set(META)]+[metadata_snapshot(old)])
 return json.dumps(rows[0] if len(rows)==1 else rows,ensure_ascii=False)

def apply_review(index,reviews,mapping,model):
 original={e['id']:e for e in index['entries']};entries=copy.deepcopy(original);applied=[];held=[];redirect={}
 for cid,r in reviews.items():
  e=entries[mapping[cid]]
  if externally_confirmed(e) or e.get('deleted') or e['review']!='suggested':raise ValueError('Refinement cannot change an externally confirmed or reviewed entry.')
  if r['action']=='uncertain' or r['confidence']=='low':held.append(cid);continue
  if r['action']=='merge':continue
  old=original[e['id']]
  if r['action']=='reject':e['review']='rejected'
  else:
   newkind=KINDS[r['category']]
   if e['kind']!=newkind:e['subtype']=''
   e['kind']=newkind
   if r['normalized_name'] and r['normalized_name']!=e['name']:
    e['aliases']=unique([*e['aliases'],e['name']]);e['name']=r['normalized_name'].strip()
  e['details']=e.get('details') or {}
  e['details'].update(confidence=r['confidence'],model=model,refinement_source=metadata_history(e['details'],old),editorial_note='Contextual API review; not independent scientific or bibliographic verification.')
  e['note']+='\nChatGPT refinement: '+r['reason'];applied.append(cid)
 for cid,r in reviews.items():
  if r['action']!='merge':continue
  if r['confidence']!='high':held.append(cid);continue
  target=r['merge_into']
  while reviews[target]['merge_into'] is not None:target=reviews[target]['merge_into']
  a=entries[mapping[cid]];b=entries[mapping[target]]
  conflicts=any(a.get(k) and b.get(k) and a[k]!=b[k] for k in ['year','publication','doi','url'])
  if conflicts or a['kind']!=b['kind'] or b['review']=='rejected' or target in held:held.append(cid);continue
  b['anchors']=unique(b['anchors']+a['anchors']);b['aliases']=unique(b['aliases']+a['aliases']+[a['name']]);b['author_ids']=unique(b['author_ids']+a['author_ids'])
  a['review']='rejected';a['note']+='\nChatGPT refinement: merged into '+b['id']
  a['details']=a.get('details') or {};a['details'].update(model=model,refinement_source=metadata_history(a['details'],original[a['id']]),editorial_note='Duplicate reference merged; original evidence retained.')
  redirect[a['id']]=b['id'];applied.append(cid)
 for e in entries.values():
  if externally_confirmed(e):continue
  e['author_ids']=unique([redirect.get(a,a) for a in e['author_ids'] if redirect.get(a,a) in entries and entries[redirect.get(a,a)]['kind']=='author' and entries[redirect.get(a,a)]['review']!='rejected'])
 for cid in applied:
  e=entries[mapping[cid]]
  if e['review']=='suggested':
   e['details']=e.get('details') or {}
   e['details']['refinement_review']=json.dumps(dict(model=model,metadata=metadata_snapshot(e),evidence=confirmation_evidence(e)[:1]),ensure_ascii=False)
 return dict(index,entries=list(entries.values())),dict(applied=len(applied),held_for_review=len(set(held)),actions=dict(collections.Counter(r['action'] for r in reviews.values())))

def main():
 project=Path(sys.argv[1]);parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');parser.add_argument('--resume-response',type=Path);parser.add_argument('--package',type=Path);parser.add_argument('--index',type=Path);parser.add_argument('--edition');parser.add_argument('--output',type=Path);args=parser.parse_args(sys.argv[2:])
 if args.check:credential(project);print('ChatGPT refinement credential configured.');return
 if not args.package or not args.edition or not args.output:parser.error('--package, --edition and --output are required')
 package=args.package.resolve();out=args.output.resolve();out.mkdir(parents=True,exist_ok=True)
 config=load(project/'scripts/indexing_trial/refinement.json')
 if not 0<config['budget_usd']<=.50 or config['model']!='gpt-5.4-mini-2026-03-17':raise ValueError('Unsupported refinement budget or model; no request sent.')
 source=args.index.resolve() if args.index else package/'indexing/index.json';summary_path=source.with_name('summary.json')
 lock=source.with_name(source.name+'.refinement.lock').open('a');fcntl.lockf(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
 original=source.read_bytes();index=json.loads(original);summary=load(summary_path);original_summary=summary_path.read_bytes();manifest=load(package/'episode.json')
 if summary['index_sha256']!=sha(original) or summary['edition']!=args.edition:raise ValueError('Local index checksum or edition mismatch.')
 basepath=(package/manifest['transcript']['reviewed_file']).resolve()
 if not basepath.is_relative_to(package):raise ValueError('Unsafe transcript path.')
 basebytes=basepath.read_bytes()
 if sha(basebytes)!=summary['baseline_sha256']:raise ValueError('Transcript checksum mismatch.')
 baseline=json.loads(basebytes)
 if baseline['episode_guid']!=summary['episode_guid']:raise ValueError('Transcript identity mismatch.')
 index,_=recover_publications(index,{(baseline['episode_guid'],args.edition):{p['id']:p['text'] for p in baseline['segments']}})
 index,_=apply_blacklist(index,load_blacklist(project))
 request,candidates,mapping,ceiling=prepare_request(index,baseline,args.edition,summary['title'],config)
 confirmed=sum(externally_confirmed(e) for e in index['entries'] if not e.get('deleted') and e['review']!='rejected')
 atomic(out/'estimate.json',dict(externally_confirmed_skipped=confirmed,candidates=len(candidates),reserved_usd=ceiling,budget_usd=config['budget_usd'],source_index_sha256=sha(original),model=config['model']))
 if not candidates:atomic(out/'result.json',dict(state='not_needed',candidates=0,externally_confirmed_skipped=confirmed,paid_requests=0,cost_usd=0));return
 if ceiling>config['budget_usd']:raise ValueError('Review exceeds the US$0.50 limit; enriched index retained. No paid request sent.')
 if args.resume_response:
  if args.resume_response.resolve()!= (out/'response.json').resolve():raise ValueError('Resume only the saved response from this output directory.')
  marker=load(out/'request-started.json');saved_request=load(out/'request.json')
  if marker['source_index_sha256']!=sha(original) or marker['request_sha256']!=sha(encoded(saved_request)):raise ValueError('Saved response does not match the current source/request hashes.')
  payload=json.loads(saved_request['input']);candidates=evidence_context(payload['candidates'],payload['passages'])
  cues={str(p['id']):p['text'] for p in baseline['segments']}
  if any(cues.get(pid)!=text for pid,text in payload['passages'].items()):raise ValueError('Saved request contains stale transcript passages.')
  mapping={int(k):v for k,v in load(out/'candidate-map.json').items()}
  if set(mapping)!={c['id'] for c in candidates}:raise ValueError('Saved candidate mapping mismatch.')
  ceiling=marker['reserved_usd'];result=load(args.resume_response)
  print('Recovering saved API response; no network request or additional charge.',flush=True)
 else:
  context=tls_context()
  key=credential(project)
  marker=out/'request-started.json'
  if marker.exists():raise ValueError('A review request already started. No automatic repetition; inspect saved usage first.')
  atomic(out/'request.json',request);atomic(out/'candidate-map.json',mapping)
  client_id=str(uuid.uuid4())
  with marker.open('x') as f:
   json.dump(dict(client_request_id=client_id,model=config['model'],reserved_usd=ceiling,request_sha256=sha(encoded(request)),source_index_sha256=sha(original),no_retries=True),f);f.flush();os.fsync(f.fileno())
  print('One synchronous ChatGPT refinement request; no automatic retry.',flush=True)
  http=urllib.request.Request('https://api.openai.com/v1/responses',data=json.dumps(request,ensure_ascii=False).encode(),headers={'Authorization':'Bearer '+key,'Content-Type':'application/json','X-Client-Request-Id':client_id})
  phase='connecting';request_id=None;started=time.monotonic()
  try:
   with urllib.request.urlopen(http,timeout=900,context=context) as response:
    phase='reading_response';request_id=response.headers.get('x-request-id')
    atomic(out/'transport.json',dict(client_request_id=client_id,request_id=request_id,http_status=response.status,trusted_ca_certificates=len(context.get_ca_certs())))
    result=json.load(response)
  except urllib.error.HTTPError as error:
   try:body=json.loads(error.read()).get('error',{})
   except Exception:body={}
   atomic(out/'api-error.json',dict(category='http_error',http_status=error.code,error_type=body.get('type'),error_code=body.get('code'),request_id=error.headers.get('x-request-id') if error.headers else None,client_request_id=client_id,elapsed_seconds=round(time.monotonic()-started,3),possible_billable_request=False))
   raise ValueError('ChatGPT API rejected the request (HTTP '+str(error.code)+'); local index retained. See api-error.json. No automatic retry.') from None
  except (urllib.error.URLError,TimeoutError,OSError,http.client.HTTPException) as error:
   problem=connection_problem(error,phase,client_id,request_id)
   problem.update(reserved_usd=ceiling,elapsed_seconds=round(time.monotonic()-started,3))
   atomic(out/'api-error.json',problem)
   raise ValueError('ChatGPT '+problem['category']+': '+problem['explanation']+' Local index retained. See api-error.json; retry only by explicit request.') from None
 atomic(out/'response.json',result);usage=result.get('usage') or {};details=usage.get('input_tokens_details') or {};tokens=usage.get('input_tokens',0);cached=details.get('cached_tokens',0);writes=details.get('cache_write_tokens',0)
 if any(type(v) is not int or v<0 for v in [tokens,cached,writes,usage.get('output_tokens')]) or tokens<cached+writes:
  atomic(out/'usage.json',dict(usage=usage,cost_usd=None,paid_requests=1,reserved_usd=ceiling));raise ValueError('Usage unavailable or invalid; local index retained. Inspect billing before retrying.')
 cost=((tokens-cached-writes)*config['input_per_million']+cached*config['cached_input_per_million']+writes*config['input_per_million']*1.25+usage.get('output_tokens',0)*config['output_per_million'])/1e6
 atomic(out/'usage.json',dict(usage=usage,cost_usd=cost,paid_requests=1,reserved_usd=ceiling))
 if result.get('status')!='completed':raise ValueError('ChatGPT review incomplete; local index retained. No retry.')
 text=''.join(c.get('text','') for m in result.get('output',[]) for c in m.get('content',[]) if c.get('type')=='output_text')
 proposals=json.loads(text);atomic(out/'proposals.json',proposals);reviews,coverage=recover_reviews(proposals,candidates)
 atomic(out/'validation.json',coverage)
 refined,changes=apply_review(index,reviews,mapping,config['model'])
 refined,_=apply_blacklist(refined,load_blacklist(project))
 if source.read_bytes()!=original or summary_path.read_bytes()!=original_summary or basepath.read_bytes()!=basebytes:raise ValueError('Local index changed during review; recommendations saved without applying.')
 atomic(out/'index-before.json',index);atomic(out/'summary-before.json',summary)
 summary.update(index_sha256=sha(encoded(refined)),entries=len(refined['entries']),categories=dict(collections.Counter(e['kind'] for e in refined['entries'])),active_entries=sum(e['review']!='rejected' and not e.get('deleted') for e in refined['entries']),active_categories=dict(collections.Counter(e['kind'] for e in refined['entries'] if e['review']!='rejected' and not e.get('deleted'))),refinement=dict(state='partial' if coverage['missing_candidates'] or coverage['invalid_candidates'] else 'completed',recovered_saved_response=bool(args.resume_response),api_rows_received=coverage['api_rows_received'],validated_candidates=coverage['validated_candidates'],missing_candidates=coverage['missing_candidates'],invalid_candidates=coverage['invalid_candidates'],externally_confirmed_skipped=confirmed,model=config['model'],cost_usd=cost,candidates=len(candidates),**changes))
 atomic(source,refined);atomic(summary_path,summary);atomic(out/'result.json',summary['refinement'])
 print(json.dumps(summary['refinement']),flush=True)

if __name__=='__main__':
 try:main()
 except Exception as error:
  if '--output' in sys.argv:
   try:
    failure_out=Path(sys.argv[sys.argv.index('--output')+1])
    failure_out.mkdir(parents=True,exist_ok=True)
    atomic(failure_out/'failure.json',dict(category='response_validation' if (failure_out/'response.json').exists() else 'refinement_error',exception_type=type(error).__name__,explanation='Refinement did not finish; active index retained. See sanitized worker log and saved response/usage.',possible_billable_request=(failure_out/'request-started.json').exists()))
   except (OSError,ValueError,IndexError):pass
  # Only our own sanitized errors are user-facing; never echo server messages.
  if isinstance(error,ValueError) and not isinstance(error,json.JSONDecodeError):print(str(error),file=sys.stderr)
  else:print('ChatGPT refinement could not complete ('+type(error).__name__+'); local index retained. See saved response/usage.',file=sys.stderr)
  sys.exit(2)
PY_REFINE

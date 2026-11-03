#!/bin/zsh
# Local-only extraction and comparison; never publishes to the Flutter asset.
set -euo pipefail
benchmark_project="${0:A:h:h}"
benchmark_python="${LOCAL_INDEX_PYTHON:-${benchmark_project}/work/local-index-benchmark/venv/bin/python}"
export HF_HOME="${benchmark_project}/work/local-index-benchmark/model-cache"
export TOKENIZERS_PARALLELISM=false
exec "$benchmark_python" -u - "$benchmark_project" "$@" <<'PY_LOCAL'
from pathlib import Path
import argparse,collections,hashlib,html,importlib.metadata,json,os,re,sys,time
project=Path(sys.argv[1]);parser=argparse.ArgumentParser()
parser.add_argument('--dictionary-only',action='store_true')
parser.add_argument('--model',default='urchade/gliner_small-v2.1')
parser.add_argument('--threshold',type=float,default=.5)
parser.add_argument('--batch-size',type=int,default=8)
args=parser.parse_args(sys.argv[2:])
if not 0<args.threshold<1 or not 1<=args.batch_size<=32: parser.error('Invalid threshold/batch size')
out=project/'outputs/local-index-benchmark';out.mkdir(parents=True,exist_ok=True)
import fcntl
lock=(out/'.benchmark.lock').open('a')
fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
def load(p):return json.loads(p.read_text())
def write(p,d):
 p.parent.mkdir(parents=True,exist_ok=True);pending=p.with_suffix(p.suffix+'.pending');pending.write_text(json.dumps(d,indent=2,ensure_ascii=False)+'\n');pending.replace(p)
def sha(b):return hashlib.sha256(b).hexdigest()
def canon(s):return re.sub(r'\s+',' ',s.casefold()).strip()
def forms(e):return {canon(x) for x in [e['name'],*e.get('spoken_names',[]),*e.get('observed_forms',[])] if x and len(x.strip())>=3 and not x.startswith('Untitled ')}
paths=[project/'outputs/indexing-trial/episode-208-karoo']+sorted(p.parent for p in (project/'outputs/indexing-app').glob('*/proposed-index.json'))
jobs=[]
for p in paths:
 s=load(p/'source_snapshot.json');index=load(p/'proposed-index.json');used=load(p/'usage.json');config=load(p/'config.json')
 if any(r['status']!='completed' for r in used['requests']):raise SystemExit('Incomplete reference '+str(p))
 if index['source_sha256']!=sha(json.dumps(s,sort_keys=True).encode()):raise SystemExit('Reference snapshot mismatch')
 key=sha(s['episode_guid'].encode())[:12];folder=out/key
 folder.mkdir(exist_ok=True)
 write(folder/'source_snapshot.json',s);write(folder/'reference-index.json',index)
 jobs.append(dict(key=key,source=s,entries=index['entries'],folder=folder,reference=str(p.relative_to(project))))
if len(jobs)!=6:raise SystemExit('Expected exactly six frozen reference episodes; inspect inventory.')
kinds=['fossil','place','paper','article','author']
labels={'fossil taxon':'fossil','animal group':'fossil','plant group':'fossil','place':'place','geological formation':'place','person':'author','research paper title':'paper','article title':'article'}
settings=dict(schema_version=1,model=args.model,threshold=args.threshold,labels=labels,window_passages=4,window_words=150,overlap_passages=1)
provenance=dict(date='2026-11-04',settings=settings,script_sha256=sha((project/'scripts/benchmark_local_indexes.zsh').read_bytes()),python=sys.version,packages={n:importlib.metadata.version(n) for n in ['gliner','torch','transformers','huggingface-hub']},references=[dict(title=j['source']['episode_title'],source_sha256=sha(json.dumps(j['source'],sort_keys=True).encode()),path=j['reference']) for j in jobs],paid_api_calls=0,warning='API suggestions are not ground truth. No model training or labels derived from test reference. All-vocabulary dictionary is deliberately optimistic; held-out vocabulary omits target-episode entries.')
previous_provenance=load(out/'provenance.json') if (out/'provenance.json').exists() else {}
write(out/'provenance.json',provenance)

def dictionary(entries):
 terms=collections.defaultdict(set)
 for e in entries:
  for f in forms(e):terms[f].add(e['kind'])
 return terms

def dictionary_extract(passages,terms):
 # Match longest alternatives at a location; ambiguous categories stay provisional.
 pattern=re.compile(r'(?<!\w)(?:'+'|'.join(re.escape(f).replace(r'\ ',r'\s+') for f in sorted(terms,key=lambda x:(-len(x),x)))+r')(?!\w)',re.I) if terms else None
 rows=[]
 for cue in passages:
  for m in pattern.finditer(cue['text']) if pattern else []:
   for kind in sorted(terms[canon(m.group())]):
    rows.append(dict(kind=kind,text=m.group(),passage_ids=[cue['id']],start=m.start(),end=m.end(),method='dictionary',needs_review=True))
 return rows

def windows(passages):
 result=[];i=0
 while i<len(passages):
  chosen=[];words=0
  for p in passages[i:i+4]:
   n=len(p['text'].split())
   if chosen and words+n>150:break
   chosen.append(p);words+=n
  text='';spans=[]
  for p in chosen:
   if text:text+='\n'
   start=len(text);text+=p['text'];spans.append((start,len(text),p['id']))
  result.append(dict(text=text,spans=spans));i+=max(1,len(chosen)-1)
 return result

model=None;device=None
if not args.dictionary_only:
 import torch
 from gliner import GLiNER
 torch.set_num_threads(4)
 device='mps' if torch.backends.mps.is_available() else 'cpu'
 print('Loading local model on '+device,flush=True)
 model=GLiNER.from_pretrained(args.model,load_tokenizer=True).to(device);model.eval()
 provenance['device']=device
 provenance['model_config']=model.config.to_dict() if hasattr(model.config,'to_dict') else str(model.config)
 # Local model file hashes pin downloaded weights/config/tokenizers without executing remote code.
 cache=Path(os.environ['HF_HOME'])
 provenance['model_files']=[dict(path=str(p.relative_to(cache)),sha256=sha(p.read_bytes())) for p in cache.rglob('*') if p.is_file() and '/blobs/' in str(p)]
 if previous_provenance.get('model_files') and (previous_provenance['model_files']!=provenance['model_files'] or previous_provenance['packages']!=provenance['packages']):
  write(out/'provenance.json',previous_provenance)
  raise SystemExit('Local weights/dependencies changed: archive the previous benchmark output before reusing this destination.')
 write(out/'provenance.json',provenance)

all_terms=dictionary([e for j in jobs for e in j['entries']]);summaries=[]
for j in jobs:
 s=j['source'];folder=j['folder'];passages=s['passages'];start=time.perf_counter()
 modes={}
 for name,terms in [('dictionary_reuse',all_terms),('dictionary_held_out',dictionary([e for other in jobs if other is not j for e in other['entries']]))]:
  began=time.perf_counter();rows=dictionary_extract(passages,terms)
  modes[name]=rows;write(folder/(name+'.json'),dict(vocabulary_terms=len(terms),seconds=time.perf_counter()-began,candidates=rows))
 if model is not None:
  win=windows(passages);rows=[];inference_seconds=0
  for b in range(0,len(win),args.batch_size):
   batch=win[b:b+args.batch_size]
   cache_key=sha(json.dumps(dict(source_sha256=sha(json.dumps(s,sort_keys=True).encode()),settings=settings,texts=[w['text'] for w in batch]),sort_keys=True).encode())
   path=folder/'model-cache'/f'{b:05}-{cache_key}.json'
   if path.exists():cached=load(path);pred=cached['predictions'];inference_seconds+=cached['seconds']
   else:
    began=time.perf_counter()
    with torch.inference_mode():pred=model.batch_predict_entities([w['text'] for w in batch],list(labels),threshold=args.threshold,flat_ner=False)
    seconds=time.perf_counter()-began;inference_seconds+=seconds
    write(path,dict(seconds=seconds,predictions=pred))
   for w,entities in zip(batch,pred):
    for e in entities:
     if not 0<=e['start']<e['end']<=len(w['text']) or w['text'][e['start']:e['end']]!=e['text']:raise SystemExit('Invalid local model span')
     ids=[pid for a,z,pid in w['spans'] if a<e['end'] and z>e['start']]
     if not ids:continue
     rows.append(dict(kind=labels[e['label']],text=e['text'],label=e['label'],score=e['score'],passage_ids=ids,window_start=w['spans'][0][2],start=e['start'],end=e['end'],method='gliner',needs_review=True))
   if b%80==0:print(s['episode_title'],min(b+len(batch),len(win)),'/',len(win),'windows',flush=True)
  # Deduplicate overlapping windows; retain highest-score candidate.
  dedup={}
  for r in rows:
   key=(r['kind'],canon(r['text']),tuple(r['passage_ids']))
   if key not in dedup or r['score']>dedup[key]['score']:dedup[key]=r
  modes['gliner']=list(dedup.values());write(folder/'gliner.json',dict(seconds=inference_seconds,windows=len(win),candidates=modes['gliner']))
  modes['hybrid_held_out']=modes['dictionary_held_out']+modes['gliner']
 stats={};missing={};extra={}
 for name,rows in modes.items():
  lookup=collections.defaultdict(set)
  for r in rows:
   for pid in r['passage_ids']:lookup[(r['kind'],pid)].add(canon(r['text']))
  values=[];miss=[]
  for e in j['entries']:
   aliases=forms(e);ids={o['passage_id'] for o in e['occurrences']}
   hits={pid for pid in ids if aliases & lookup[(e['kind'],pid)]}
   values.append(dict(kind=e['kind'],entry=bool(hits),hits=len(hits),total=len(ids)))
   if not hits:miss.append(dict(kind=e['kind'],name=e['name'],passage_ids=sorted(ids),forms=sorted(aliases)))
  stats[name]={}
  for kind in kinds+['all']:
   v=[r for r in values if kind=='all' or r['kind']==kind]
   stats[name][kind]=dict(reference_entries=len(v),matched_entries=sum(r['entry'] for r in v),reference_passage_mentions=sum(r['total'] for r in v),matched_passage_mentions=sum(r['hits'] for r in v))
  missing[name]=miss
  known=collections.defaultdict(set)
  for e in j['entries']:
   for o in e['occurrences']:known[(e['kind'],o['passage_id'])].update(forms(e))
  extras=[r for r in rows if not any(canon(r['text']) in known[(r['kind'],pid)] for pid in r['passage_ids'])]
  extra[name]=extras
  stats[name]['unmatched_candidates']=len(extras)
 write(folder/'comparison.json',dict(title=s['episode_title'],stats=stats,missing=missing))
 write(folder/'unmatched-candidates.json',extra)
 by_id={p['id']:p for p in passages}
 sample=['# Local candidates requiring human review','', 'Unmatched does not mean incorrect. Existing API indexes are incomplete suggestions. Person candidates do not establish authorship; title candidates do not identify a publication.','']
 for name in ['gliner','dictionary_held_out']:
  sample+=['## '+name,'']
  for r in extra.get(name,[])[:50]:
   sample += [f"- **{r['text']}** ({r['kind']}); passages {', '.join(map(str,r['passage_ids']))}", '  > '+' '.join(by_id[pid]['text'] for pid in r['passage_ids']),'']
 (folder/'REVIEW_SAMPLE.md').write_text('\n'.join(sample))
 summaries.append(dict(title=s['episode_title'],episode=s['episode_number'],key=j['key'],passages=len(passages),stats=stats,wall_seconds=time.perf_counter()-start))
 write(out/'summary.json',dict(episodes=summaries,paid_api_calls=0))
 print('Completed',s['episode_title'],flush=True)
report=['# Local indexing benchmark — 4 November 2026','', 'No paid API calls. App indexes unchanged. All six fixed transcript snapshots processed. The comparison reference is existing API suggestions, not independently reviewed truth; agreement percentages are not accuracy or scientific recall.','', 'Known-name reuse includes the target episode’s vocabulary and is an optimistic upper bound. Held-out matching excludes the target episode entirely. GLiNER uses generic category labels only; person candidates are provisional Authors and publications lack verified authors/metadata.','', '| Episode | Reference entries | Reuse agreement | Held-out agreement | GLiNER agreement | Hybrid held-out agreement |','|---|---:|---:|---:|---:|---:|']
for e in summaries:
 def pct(mode):
  if mode not in e['stats']:return 'not run'
  v=e['stats'][mode]['all'];return f"{100*v['matched_entries']/max(1,v['reference_entries']):.1f}%"
 n=e['stats']['dictionary_reuse']['all']['reference_entries']
 report.append(f"| {e['episode']} — {e['title']} | {n} | {pct('dictionary_reuse')} | {pct('dictionary_held_out')} | {pct('gliner')} | {pct('hybrid_held_out')} |")
report+=['', '## Category totals','', '| Method | Category | Matched / reference entries | Matched / reference passage mentions |','|---|---|---:|---:|']
for mode in summaries[0]['stats']:
 for kind in kinds:
  vals=[e['stats'][mode][kind] for e in summaries]
  totals={k:sum(v[k] for v in vals) for k in vals[0]}
  report.append(f"| {mode} | {kind} | {totals['matched_entries']} / {totals['reference_entries']} | {totals['matched_passage_mentions']} / {totals['reference_passage_mentions']} |")
report+=['', '## Interpretation','', 'Use a reviewed shared vocabulary for inexpensive repeatable matching. Use local model output as a review queue, not an automatic replacement for publication/author identification or scientific normalization. Unknown names and descriptive paper labels can fail strict string agreement even when a useful candidate is found. Conversely a matching name need not establish correct meaning.','', 'The same entity appearing in several episodes is counted per episode. Reference mentions are deduplicated by passage ID; ranges are not used for scoring. Text is matched case-insensitively with whitespace normalization and word boundaries; no speculative singularization or fuzzy matching. Longer dictionary matches suppress nested shorter terms at the same position. Spans crossing passages are retained in local model candidates. Review samples are deterministic examples, not a random precision audit.','', 'Inspect comparison.json for misses and unmatched-candidates.json / REVIEW_SAMPLE.md for additional candidates. A manually labeled independent sample is required before any production accuracy claim. Dependencies are isolated under work/local-index-benchmark; model files and inference batches are cached, with source/model/config hashes. Saved runtime includes inference on first-run batches; wall time of a resumed episode may be shorter.','', 'No Flutter code, app assets, transcripts or published registries changed. No bibliography or author relationships fabricated. No builds, app launches or Git mutations. Local benchmark execution was explicitly requested; unrelated test suites were not run.','']
(out/'REPORT.md').write_text('\n'.join(report))
print('Report:',out/'REPORT.md',flush=True)
PY_LOCAL

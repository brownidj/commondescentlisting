#!/bin/zsh
# Offline local index, separate from the immutable audio/transcript manifest.
set -euo pipefail
local_project="${0:A:h:h}"
local_python="${LOCAL_INDEX_PYTHON:-${local_project}/work/local-index-benchmark/venv/bin/python}"
[[ -x "$local_python" ]] || { print -u2 'Local indexing environment missing: work/local-index-benchmark/venv'; exit 2; }
export HF_HOME="${local_project}/work/local-index-benchmark/model-cache"
export HF_HUB_OFFLINE=1
export TOKENIZERS_PARALLELISM=false
exec "$local_python" -u - "$local_project" "$@" <<'PY_INDEX'
from pathlib import Path
import argparse,collections,hashlib,json,os,re,sys,time
project=Path(sys.argv[1]);parser=argparse.ArgumentParser()
parser.add_argument('--check',action='store_true')
parser.add_argument('--package',type=Path)
parser.add_argument('--edition')
parser.add_argument('--output',type=Path)
args=parser.parse_args(sys.argv[2:]);model_name='urchade/gliner_small-v2.1'
from gliner import GLiNER
import torch
cache=Path(os.environ['HF_HOME'])/'hub/models--urchade--gliner_small-v2.1'
if not list(cache.glob('snapshots/*/gliner_config.json')):raise SystemExit('Offline local indexing model missing. Restore work/local-index-benchmark/model-cache before preparation.')
if args.check:print('Offline local indexing environment ready.');raise SystemExit(0)
if not args.package or not args.output:parser.error('--package and --output required')
package=args.package.resolve();out=args.output.resolve();out.mkdir(parents=True,exist_ok=True)
def sha(b):return hashlib.sha256(b).hexdigest()
def load(p):return json.loads(p.read_text())
def write(p,d):
 p.parent.mkdir(parents=True,exist_ok=True);tmp=p.with_suffix(p.suffix+'.pending');tmp.write_text(json.dumps(d,indent=2,ensure_ascii=False)+'\n');tmp.replace(p)
def canon(s):return re.sub(r'\s+',' ',s.casefold()).strip()
m=load(package/'episode.json');guid=m['episode_guid'];edition=args.edition or m['audio']['identity']
def artifact(relative):
 p=(package/relative).resolve()
 if not p.is_relative_to(package):raise SystemExit('Unsafe package path')
 b=p.read_bytes();record=next((r for r in m['artifacts'] if r['file']==relative),None)
 if not record or sha(b)!=record['sha256']:raise SystemExit('Transcript artifact checksum mismatch')
 return b
base_bytes=artifact(m['transcript']['reviewed_file']);base=json.loads(base_bytes)
alignment=json.loads(artifact(m['transcript']['alignment_file']))
if alignment['source_transcript_sha256']!=sha(base_bytes) or alignment['audio_identity']!=m['audio']['identity'] or base['episode_guid']!=guid:raise SystemExit('Transcript/audio identity mismatch')
passages=base['segments'];by_id={p['id']:p for p in passages}
if len(by_id)!=len(passages) or len(alignment['segments'])!=len(passages):raise SystemExit('Invalid passage coverage')
started=time.perf_counter();vocab=load(project/'flutter_app/assets/data/contextual_indexes.json')['entries']
local_asset=project/'flutter_app/assets/data/local_indexes.json'
if local_asset.exists():vocab+=load(local_asset)['entries']
terms=collections.defaultdict(list)
for e in vocab:
 if e['review']=='rejected':continue
 for f in {canon(x) for x in [e['name'],*e['aliases']] if len(x.strip())>=3}:
  terms[f].append(e)
pattern=re.compile(r'(?<!\w)(?:'+'|'.join(re.escape(x).replace(r'\ ',r'\s+') for x in sorted(terms,key=lambda x:(-len(x),x)))+r')(?!\w)',re.I) if terms else None
entries={};blocked={'i','we','you','you guys','he','she','they','it','will','david','facebook','twitter','youtube','wordpress','listenerville'}
time_terms={'mesozoic','paleozoic','cenozoic','jurassic','triassic','cretaceous','permian','cambrian','ordovician','silurian','devonian','carboniferous','precambrian'}
def add(kind,name,pid,quote,method,score=None,subtype=''):
 normalized=canon(name)
 if len(normalized)<3 or normalized in blocked or (kind=='place' and normalized in time_terms):return
 cue=by_id[pid]
 if quote not in cue['text']:raise SystemExit('Index quote is not literal')
 key=(kind,normalized)
 if key not in entries:
  ident='local:'+sha((guid+'\0'+kind+'\0'+normalized).encode())[:24]
  entries[key]=dict(id=ident,kind=kind,name=name,review='suggested',aliases=[],subtype=subtype or ('person' if kind=='author' else ''),year=None,publication='',doi='',url='',link_verified=False,author_ids=[],anchors=[],note='Offline local suggestion; requires review.',details=dict(spoken=[],description='Local name/reference candidate. Person detection does not establish authorship; publication metadata and links are unverified.',confidence='unreviewed',normalizations=[],editorial_note='Locally generated; not a verified scientific or bibliographic identification.',bibliography='',original_publication='',sources=[],model=model_name))
 e=entries[key]
 if quote not in e['aliases']:e['aliases'].append(quote)
 if quote not in e['details']['spoken']:e['details']['spoken'].append(quote)
 anchor=dict(guid=guid,quote=quote,passage_id=pid,edition=edition,passage_text=cue['text'])
 if anchor not in e['anchors']:e['anchors'].append(anchor)
for p in passages:
 for hit in pattern.finditer(p['text']) if pattern else []:
  for e in terms[canon(hit.group())]:add(e['kind'],e['name'],p['id'],hit.group(),'dictionary',subtype=e.get('subtype',''))
torch.set_num_threads(4);device='mps' if torch.backends.mps.is_available() else 'cpu'
model=GLiNER.from_pretrained(model_name,local_files_only=True).to(device);model.eval()
labels={'taxon':'fossil','animal group':'fossil','plant group':'fossil','place':'place','geological formation':'place','person':'author','research paper title':'paper','article title':'article'}
# Per-passage spans avoid generating partial evidence from cross-passage names.
for start in range(0,len(passages),8):
 batch=passages[start:start+8]
 with torch.inference_mode():pred=model.inference([p['text'] for p in batch],list(labels),threshold=.5,flat_ner=False)
 for p,hits in zip(batch,pred):
  for h in hits:
   text=p['text'];a,z=h['start'],h['end']
   if not 0<=a<z<=len(text) or text[a:z]!=h['text']:raise SystemExit('Invalid model span')
   if (a and text[a-1].isalnum()) or (z<len(text) and text[z].isalnum()):continue
   add(labels[h['label']],h['text'],p['id'],h['text'],'gliner',h['score'])
 if start%80==0:print('LOCAL_INDEX_PROGRESS '+str(min(start+8,len(passages)))+' '+str(len(passages)),flush=True)
 # Explicit reference cues preserve candidate discussions without inventing titles.
 for p in batch:
  for match in re.finditer(r'\b(paper|study|research|article)\b',p['text'],re.I):
   kind='article' if match.group().lower()=='article' else 'paper'
   label=p['text'].strip()
   add(kind,label,p['id'],match.group(),'reference-cue',subtype='popular_article' if kind=='article' else 'research_paper')
document=dict(schema_version=1,entries=sorted(entries.values(),key=lambda e:(e['kind'],e['name'].casefold())))
write(out/'index.json',document)
counts={k:sum(e['kind']==k for e in entries.values()) for k in ['fossil','place','paper','article','author']}
summary=dict(schema_version=1,episode_guid=guid,edition=edition,title=m['metadata']['title'],passages=len(passages),entries=len(entries),categories=counts,seconds=round(time.perf_counter()-started,2),method='dictionary + offline GLiNER + explicit reference cues',model=model_name,device=device,paid_api_calls=0,index_sha256=sha((out/'index.json').read_bytes()),baseline_sha256=sha(base_bytes),audio_identity=m['audio']['identity'],review_required=True,notes='Reference cues are unverified candidate discussions, not identified publications. Names and classifications require review.')
write(out/'summary.json',summary)
print(json.dumps(summary),flush=True)
PY_INDEX

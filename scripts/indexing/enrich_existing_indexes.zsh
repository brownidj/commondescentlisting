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
def load(p):return json.loads(p.read_text())
def sha(b):return hashlib.sha256(b).hexdigest()
def enc(d):return (json.dumps(d,indent=2,ensure_ascii=False)+'\n').encode()
def write(p,d):
 p.parent.mkdir(parents=True,exist_ok=True);tmp=p.with_name(p.name+'.enrichment-pending');tmp.write_bytes(enc(d));tmp.replace(p)
def canon(s):return ' '.join(''.join(c for c in unicodedata.normalize('NFKD',s.casefold()) if not unicodedata.combining(c)).replace('–','-').replace('’',"'").split())
def unique(rows):return list({json.dumps(x,sort_keys=True,ensure_ascii=False):x for x in rows}.values())
def active(e):return e.get('review')!='rejected' and not e.get('deleted')
def helpers(file,marker):
 text=(root/'scripts/indexing'/file).read_text().split("<<'"+marker+"'\n",1)[1].rsplit('\n'+marker,1)[0]
 scope={'__name__':'enrichment_helpers'};exec(compile(text,file,'exec'),scope);return scope
ext=helpers('lookup_external_datasets.zsh','PY_EXTERNAL');pb=helpers('lookup_pbdb.zsh','PY_PBDB');cr=helpers('lookup_crossref.zsh','PY_CROSSREF')
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
# At least one exact active-edition anchor must support a lookup. Stale anchors remain untouched.
def valid_anchors(e):return [a for a in e['anchors'] if isinstance(a.get('passage_text'),str) and a.get('passage_text')==baselines.get((a['guid'],a.get('edition')),{}).get(a.get('passage_id')) and a.get('quote') and a['quote'] in a['passage_text']]
locks={p:threading.Lock() for p in ['pbdb','col','crossref','macrostrat','geonames']};last=collections.defaultdict(float);sent=collections.Counter();halt={};cache_hits=collections.Counter()
def fetch(provider,url,text=False):
 folder={'pbdb':'pbdb-cache','crossref':'crossref-cache'}.get(provider,'external-datasets-cache');p=root/'work'/folder/(sha(url.encode())+'.json')
 with locks[provider]:
  if p.exists():
   d=load(p);assert d['request_url']==url;cache_hits[provider]+=1;return d
  if not args.online:raise ValueError('No cached response')
  if provider in halt:raise ValueError(halt[provider])
  if sent[provider]>=1600:raise ValueError('Provider request ceiling reached')
  time.sleep(max(0,1-(time.monotonic()-last[provider])));last[provider]=time.monotonic();sent[provider]+=1
  try:
   req=urllib.request.Request(url,headers={'User-Agent':'CommonDescentListing-IndexEnrichment/0.2','Accept':'application/json'})
   with urllib.request.urlopen(req,timeout=25) as response:
    b=response.read(3_000_001)
    if len(b)>3_000_000:raise ValueError('Response exceeds 3 MB')
    d=dict(request_url=url,retrieved_at_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),body_sha256=sha(b),last_modified=response.headers.get('Last-Modified'),payload=b.decode('utf-8-sig') if text else json.loads(b))
   write(p,d);return d
  except urllib.error.HTTPError as e:
   if e.code in [429,503]:halt[provider]='Service backoff HTTP '+str(e.code)
   raise

def record(provider,c,d):return dict(provider=provider,record=c,retrieved_at_utc=d['retrieved_at_utc'],request_url=d['request_url'])
# Existing country/region cache plus one bounded town extract; CC-BY attribution.
country=fetch('geonames','https://download.geonames.org/export/dump/countryInfo.txt',True)
admin=fetch('geonames','https://download.geonames.org/export/dump/admin1CodesASCII.txt',True)
geo=ext['geo_records'](country['payload'],admin['payload']);citypath=root/'work/external-datasets-cache/cities1000.zip'
if not citypath.exists():
 if not args.online:raise SystemExit('Town extract not cached; use --online')
 url='https://download.geonames.org/export/dump/cities1000.zip'
 with urllib.request.urlopen(url,timeout=40) as r:
  b=r.read(16_000_001)
  if len(b)>16_000_000:raise ValueError('Town archive exceeds 16 MB')
 citypath.write_bytes(b);write(citypath.with_suffix('.source.json'),dict(url=url,retrieved_at_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),sha256=sha(b),license='GeoNames CC-BY'))
with zipfile.ZipFile(citypath) as z:
 if z.getinfo('cities1000.txt').file_size>80_000_000:raise ValueError('Town extract too large')
 for line in io.TextIOWrapper(z.open('cities1000.txt'),encoding='utf-8'):
  f=line.rstrip('\n').split('\t');geo.append(dict(id=f[0],name=f[1],aliases=[f[2]],level='town/city',country_code=f[8],admin_code=f[8]+'.'+f[10],latitude=f[4],longitude=f[5]))
def geo_source(c):
 if c['level']=='country':return country
 if c['level']=='first-level region':return admin
 meta=load(citypath.with_suffix('.source.json'));return dict(request_url=meta['url'],retrieved_at_utc=meta['retrieved_at_utc'])
geo_by_name=collections.defaultdict(list)
for r in geo:
 for n in {canon(r['name']),*[canon(x) for x in r['aliases']]}:
  if n:geo_by_name[n].append(r)
interval_response=fetch('macrostrat','https://macrostrat.org/api/v2/defs/intervals?all');intervals=ext['macro_candidates'](interval_response['payload'],interval_response['request_url'])
interval_names=collections.defaultdict(list)
for r in intervals:interval_names[canon(r['name'])].append(r)
paleo={'gondwana','gondwanaland','gondwanan','laurasia','pangaea','pangea','rodinia','pannotia','columbia','nuna','kenorland','laurentia','baltica','avalonia','siberia paleocontinent'}
corrections={'didelphys virginiana':'Didelphis virginiana','adelophthalmus pyrei':'Adelophthalmus pyrrhae','chongnyenia vioningensis':'Changmiania liaoningensis'}
def resolve(key,group):
 kind,name=key;e=max(group,key=lambda e:len(valid_anchors(e)));anchors=unique([a for e in group for a in valid_anchors(e)])
 row=dict(kind=kind,name=e['name'],source_ids=sorted({e['id'] for e in group}),anchors=anchors,source_anchors=unique([a for e in group for a in e['anchors']]),matched=[],errors=[],status='hard_unresolved',reason='No unique external identity established')
 if not anchors:row.update(status='stale_evidence',reason='No exact active-edition transcript evidence');return row
 if name in paleo:
  row.update(status='applied',target_kind='place',target_name=e['name'],reason='Paleogeographic place; retained in Places as instructed by David',confirmed_by='David');return row
 if name in ['saltville','saltville, virginia']:
  c=[r for r in geo_by_name['saltville'] if r['country_code']=='US' and r['admin_code']=='US.VA']
  row.update(status='applied',target_kind='place',target_name='Saltville, Virginia',reason='Location confirmed by David',confirmed_by='David')
  if len(c)==1:row['matched']=[record('geonames',dict(c[0],url='https://www.geonames.org/'+c[0]['id']+'/'),geo_source(c[0]))]
  return row
 if kind=='fossil':
  query=corrections.get(name,e['name']);selected=[]
  try:
   url=pb['query_url']({'name':query});d=fetch('pbdb',url);payload=d['payload']
   if payload.get('errors') or not isinstance(payload.get('records'),list):raise ValueError('Invalid PBDB response')
   candidates=[pb['metadata'](c,query) for c in payload['records']];exact=[c for c in candidates if canon(c['name'])==canon(query)]
   identities={c['accepted_id'] or c['taxon_id'] for c in exact}
   if len(identities)==1 and exact:
    c=exact[0];row['matched'].append(record('pbdb',c,d));selected.append(c['accepted_name'] or c['name'])
  except Exception as ex:row['errors'].append('PBDB: '+str(ex))
  try:
   url=ext['query_url']('col',{'name':query},316595);d=fetch('col',url);cs=ext['col_candidates'](d['payload'],316595)
   cs=[c for c in cs if canon(c['name'])==canon(query) and c.get('service_match_type') not in ['higherrank','alternative'] and c.get('status') in ['accepted','synonym']]
   if len(cs)==1 and cs[0].get('accepted_name'):
    c=cs[0];row['matched'].append(record('col',c,d));selected.append(c['accepted_name'])
  except Exception as ex:row['errors'].append('CoL: '+str(ex))
  if selected and len({canon(n) for n in selected})==1:
   target=selected[0] if len({m['provider'] for m in row['matched']})>1 or canon(selected[0])==canon(query) else query
   row.update(status='applied',target_name=target,reason='Unique exact scientific-name identity; accepted-name change requires agreement across both taxonomy sources')
  elif selected:row['reason']='External sources disagree on accepted name; original heading retained'
 elif kind=='place':
  # Geological intervals stay in the existing Places category.
  cs=interval_names.get(name,[])
  if cs:
   ids={(c['base_age_ma'],c['top_age_ma']) for c in cs}
   if len(ids)==1:row.update(status='applied',reason='Exact geological interval; retained in existing Places category',matched=[record('macrostrat',cs[0],interval_response)])
  else:
   cs=geo_by_name.get(name,[])
   countries=[c for c in cs if c['level']=='country']
   if len(countries)==1 and any(e.get('subtype')=='country' for e in group):cs=countries
   if len(cs)>1:
    # Require an explicit geographic qualifier, not merely the most populous town.
    context=' '.join(a['passage_text'] for a in anchors)
    hints=[]
    for c in cs:
     code=c['country_code'];country_name=next((r['name'] for r in geo_by_name.get(canon(code),[]) if r['level']=='country'),None)
     if country_name and canon(country_name)!=name and re.search(r'\b'+re.escape(country_name)+r'\b',context,re.I):hints.append(c)
    if len(hints)==1:cs=hints
   if len(cs)==1:
    c=dict(cs[0],url='https://www.geonames.org/'+cs[0]['id']+'/');row.update(status='applied',reason='Unique exact geographic name with available qualifiers',matched=[record('geonames',c,geo_source(c))])
   elif len(cs)>1:row['reason']='Ambiguous geographic name: '+', '.join(c['name']+' ('+c['country_code']+')' for c in cs[:8])
   elif re.search(r'\b(formation|group|limestone|sandstone|shale|supergroup)\b',name):
    q=re.sub(r'\b(formation|group|limestone|sandstone|shale|supergroup)\b','',e['name'],flags=re.I).strip()
    try:
     url=ext['query_url']('macrostrat',{'name':q,'kind':'strat'});d=fetch('macrostrat',url);cs=ext['macro_candidates'](d['payload'],url)
     exact=[c for c in cs if canon(c['name'])==name]
     # Stratigraphic homonyms require location metadata: even a sole text hit is insufficient.
     row['reason']='Stratigraphic identity needs geographic correlation; '+str(len(exact))+' exact source records'
     row['candidates']=exact[:5]
    except Exception as ex:row['errors'].append('Macrostrat: '+str(ex))
 elif kind in ['paper','article']:
  doi=next((x.get('doi') for x in group if x.get('doi')),None)
  # Specific title/context searches are allowed, but only exact titles or explicit DOI resolve identity.
  if doi or len(re.findall(r'\w+',name))>=5:
   try:
    url=cr['query_url']({'doi':doi} if doi else {'query':e['name'][:950]},'');d=fetch('crossref',url);message=d['payload'].get('message',{})
    items=[message] if doi else message.get('items',[]);cs=[cr['metadata'](i) for i in items]
    normtitle=lambda s:re.sub(r'[^\w]+',' ',canon(s)).strip()
    exact=[c for c in cs if (doi and canon(c['doi'])==canon(doi)) or (len(normtitle(c['title']).split())>=5 and normtitle(c['title']) in normtitle(e['name']))]
    if len(exact)==1:
     row.update(status='applied',reason='Explicit DOI or complete exact publication title',matched=[record('crossref',exact[0],d)])
    else:row['reason']='Publication topic or author clues do not uniquely identify a work';row['candidates']=cs[:3]
   except Exception as ex:row['errors'].append('Crossref: '+str(ex))
  else:row['reason']='Insufficient publication details for a specific bibliographic lookup'
 elif kind=='author':row['reason']='Person identity/authorship not established by a specific matched publication'
 if row['errors'] and row['status']!='applied':row['status']='lookup_error'
 return row
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
# Crossref author evidence is used only if that author already appears as an index heading.
authors=collections.defaultdict(list)
for r in results:
 for m in r['matched']:
  if m['provider']=='crossref':
   for a in m['record']['authors']:
    n=(a.get('given','')+' '+a.get('family','')).strip() or a.get('name','')
    if n:authors[canon(n)].append((a,m))
for r in results:
 if r['kind']=='author' and canon(r['name']) in authors:
  matches=authors[canon(r['name'])]
  if len({(a.get('orcid',''),canon(a.get('given','')+' '+a.get('family',''))) for a,m in matches})==1:
   r.update(status='applied',reason='Exact named author of a resolved publication',matched=[m for a,m in matches])
write(out/'results.json',dict(schema_version=1,results=results,requests_sent=dict(sent),cache_hits=dict(cache_hits),paid_api_calls=0,catalogue_of_life_release=316595,source_files=[dict(path=str(p),sha256=sha(b)) for p,b in before.items()]))
# Snapshot compare-and-swap plus app-compatible advisory lock. No network while locked.
if args.apply:
 lock=Path(str(registry)+'.lock').open('a');fcntl.lockf(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
 if any(p.read_bytes()!=b for p,b in before.items()):raise SystemExit('Input changed during lookup. No files changed; rerun using the cache.')
 bykey={(r['kind'],canon(r['name'])):r for r in results};changes=[];merges=[]
 for p,d in docs.items():
  for e in d['entries']:
   if not active(e):continue
   row=bykey[(e['kind'],canon(e['name']))]
   if row['status']!='applied' or not valid_anchors(e):continue
   old=e['name'];e['name']=row.get('target_name',old);e['kind']=row.get('target_kind',e['kind'])
   if old!=e['name']:e['aliases']=unique([*e.get('aliases',[]),old])
   details=e.get('details') or {};sources=details.get('sources',[]);paragraphs=[]
   for match in row['matched']:
    c=match['record'];url=c.get('url','');provider=match['provider']
    if url:sources.append(dict(url=url,label={'pbdb':'Paleobiology Database','col':'Catalogue of Life 2026-10-14 (316595)','geonames':'GeoNames — CC-BY','macrostrat':'Macrostrat — CC-BY 4.0','crossref':'Crossref'}[provider]))
    paragraphs.append(provider+': '+json.dumps({k:v for k,v in c.items() if k not in ['raw_record','review_status','issues']},ensure_ascii=False)+'. Retrieved '+match['retrieved_at_utc'])
    if provider=='crossref' and e['kind'] in ['paper','article']:
     e.update(doi=c['doi'],url=c['url'],link_verified=True,publication=c['journal'] or c['publisher'])
     dates=c.get('dates',{});parts=next((v[0] for v in dates.values() if v and v[0]),[])
     if parts:e['year']=parts[0]
   details['sources']=unique(sources)
   description=details.get('description','');details['description']='\n\n'.join(unique([s for s in description.split('\n\n') if s]+paragraphs))
   note='Automatic external-source enrichment authorised by David, 4 November 2026. '+row['reason']+'. Transcript wording retained.'
   details['editorial_note']='\n'.join(unique([*details.get('editorial_note','').splitlines(),note]));e['details']=details
   # A database identity is not human review. Preserve existing review state except explicit user confirmations.
   if row.get('confirmed_by')=='David':e['review']='confirmed'
   changes.append(dict(path=str(p),id=e['id'],old_name=old,name=e['name'],kind=e['kind']))
  # Exact category/name duplicates only; include all anchored evidence and redirect author links.
  groups=collections.defaultdict(list)
  for e in d['entries']:
   if active(e):groups[(e['kind'],canon(e['name']))].append(e)
  redirects={}
  for key,group in groups.items():
   if len(group)<2:continue
   group.sort(key=lambda e:(e.get('review')!='confirmed',e['id']));target=group[0]
   for variant in group[1:]:
    target['anchors']=unique(target['anchors']+variant['anchors']);target['aliases']=unique(target.get('aliases',[])+variant.get('aliases',[])+[variant['name']])
    target['variant_ids']=unique(target.get('variant_ids',[])+[variant['id']]+variant.get('variant_ids',[]))
    target['author_ids']=unique(target.get('author_ids',[])+variant.get('author_ids',[]))
    td=target.get('details') or {};target['details']=td;vd=variant.get('details') or {}
    td['sources']=unique(td.get('sources',[])+vd.get('sources',[]))
    td['description']='\n\n'.join(unique([x for x in (td.get('description','')+'\n\n'+vd.get('description','')).split('\n\n') if x]))
    variant['review']='rejected';variant['note']=variant.get('note','')+'\nDuplicate merged into '+target['id']+' during authorised external enrichment.';redirects[variant['id']]=target['id'];merges.append(dict(path=str(p),source=variant['id'],target=target['id']))
  for e in d['entries']:
   if active(e):e['author_ids']=unique([redirects.get(i,i) for i in e.get('author_ids',[])])
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

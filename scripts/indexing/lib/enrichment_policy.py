"""Shared enrichment policy. Library only; ZSH commands own all entry points."""
from index_policy import apply_blacklist,load_blacklist,blocked
from crossref_publications import resolve_publication,attach_authors,valid_dates
from pathlib import Path
import collections,copy,datetime,hashlib,io,json,re,threading,time,unicodedata,urllib.request,urllib.error,zipfile,uuid

def load(p):return json.loads(p.read_text())
def sha(b):return hashlib.sha256(b).hexdigest()
def enc(d):return (json.dumps(d,indent=2,ensure_ascii=False)+'\n').encode()
def write(p,d):
 p.parent.mkdir(parents=True,exist_ok=True);tmp=p.with_name(p.name+'.enrichment-'+uuid.uuid4().hex+'.pending');tmp.write_bytes(enc(d));tmp.replace(p)
def canon(s):return ' '.join(''.join(c for c in unicodedata.normalize('NFKD',s.casefold()) if not unicodedata.combining(c)).replace('–','-').replace('’',"'").split())
def unique(rows):return list({json.dumps(x,sort_keys=True,ensure_ascii=False):x for x in rows}.values())
def active(e):return e.get('review')!='rejected' and not e.get('deleted')
def helpers(root,file,marker):
 text=(root/'scripts/indexing'/file).read_text().split("<<'"+marker+"'\n",1)[1].rsplit('\n'+marker,1)[0]
 scope={'__name__':'enrichment_helpers'};exec(compile(text,file,'exec'),scope);return scope

def record(provider,c,d):return dict(provider=provider,record=c,retrieved_at_utc=d['retrieved_at_utc'],request_url=d['request_url'])

class EnrichmentPolicy:
 def __init__(self,root,baselines,online=False,config=None):
  self.root=Path(root);self.baselines=baselines;self.online=online
  self.config=config or load(self.root/'scripts/indexing/enrichment_sources.json')
  self.ext=helpers(self.root,'lookup_external_datasets.zsh','PY_EXTERNAL');self.pb=helpers(self.root,'lookup_pbdb.zsh','PY_PBDB');self.cr=helpers(self.root,'lookup_crossref.zsh','PY_CROSSREF')
  self.paleo=set(self.config['paleocontinents']);self.corrections=self.config['approved_spellings']
  self.locks={p:threading.Lock() for p in ['pbdb','col','crossref','macrostrat','geonames']}
  self.last=collections.defaultdict(float);self.sent=collections.Counter();self.halt={};self.cache_hits=collections.Counter()
  self.places_lock=threading.Lock();self.places_ready=False;self.place_errors=[]
  self.geo_by_name=collections.defaultdict(list);self.interval_names=collections.defaultdict(list);self.interval_response={}
 def valid_anchors(self,e):
  return [a for a in e.get('anchors',[]) if isinstance(a.get('passage_text'),str) and a['passage_text']==self.baselines.get((a.get('guid'),a.get('edition')),{}).get(a.get('passage_id')) and isinstance(a.get('quote'),str) and a['quote'] and a['quote'] in a['passage_text']]
 def fetch(self,provider,url,text=False):
  folder={'pbdb':'pbdb-cache','crossref':'crossref-cache'}.get(provider,'external-datasets-cache');p=self.root/'work'/folder/(sha(url.encode())+'.json')
  with self.locks[provider]:
   if p.exists():
    d=load(p)
    if d['request_url']!=url:raise ValueError('Cache URL mismatch')
    self.cache_hits[provider]+=1;return d
   if not self.online:raise ValueError('Offline: source response not cached')
   if provider in self.halt:raise ValueError(self.halt[provider])
   if self.sent[provider]>=self.config['max_requests_per_provider']:raise ValueError('Provider request ceiling reached')
   time.sleep(max(0,self.config['request_spacing_seconds']-(time.monotonic()-self.last[provider])));self.last[provider]=time.monotonic();self.sent[provider]+=1
   try:
    req=urllib.request.Request(url,headers={'User-Agent':'CommonDescentListing-IndexEnrichment/1.0','Accept':'application/json'})
    with urllib.request.urlopen(req,timeout=self.config['timeout_seconds']) as response:
     b=response.read(3_000_001)
     if len(b)>3_000_000:raise ValueError('Response exceeds 3 MB')
     d=dict(request_url=url,retrieved_at_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),body_sha256=sha(b),last_modified=response.headers.get('Last-Modified'),payload=b.decode('utf-8-sig') if text else json.loads(b))
    write(p,d);return d
   except urllib.error.HTTPError as exc:
    if exc.code in [401,403,429] or exc.code>=500:self.halt[provider]='Service backoff HTTP '+str(exc.code)
    raise
   except (urllib.error.URLError,TimeoutError) as exc:
    self.halt[provider]='Source unavailable: '+str(exc);raise
 def ensure_places(self):
  with self.places_lock:
   if self.places_ready:return
   self.places_ready=True;geo=[];self.country=None;self.admin=None;self.citymeta=None
   for field,file in [('country','countryInfo.txt'),('admin','admin1CodesASCII.txt')]:
    try:setattr(self,field,self.fetch('geonames','https://download.geonames.org/export/dump/'+file,True))
    except Exception as exc:self.place_errors.append('GeoNames '+field+': '+str(exc))
   try:
    if self.country:geo+=self.ext['geo_records'](self.country['payload'],'')
    if self.admin:geo+=self.ext['geo_records']('',self.admin['payload'])
   except Exception as exc:self.place_errors.append('GeoNames parsing: '+str(exc))
   citypath=self.root/'work/external-datasets-cache/cities1000.zip';url='https://download.geonames.org/export/dump/cities1000.zip'
   try:
    if not citypath.exists():
     if not self.online:raise ValueError('Offline: town extract not cached')
     with urllib.request.urlopen(url,timeout=self.config['timeout_seconds']) as response:
      b=response.read(16_000_001)
      if len(b)>16_000_000:raise ValueError('Town archive exceeds 16 MB')
     citypath.parent.mkdir(parents=True,exist_ok=True);tmp=citypath.with_suffix('.pending.zip');tmp.write_bytes(b);tmp.replace(citypath)
     write(citypath.with_suffix('.source.json'),dict(url=url,retrieved_at_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),sha256=sha(b),license='GeoNames CC-BY'))
    self.citymeta=load(citypath.with_suffix('.source.json'))
    if sha(citypath.read_bytes())!=self.citymeta['sha256']:raise ValueError('Town archive checksum mismatch')
    with zipfile.ZipFile(citypath) as z:
     if z.getinfo('cities1000.txt').file_size>80_000_000:raise ValueError('Town extract too large')
     for line in io.TextIOWrapper(z.open('cities1000.txt'),encoding='utf-8'):
      f=line.rstrip('\n').split('\t');geo.append(dict(id=f[0],name=f[1],aliases=[f[2]],level='town/city',country_code=f[8],admin_code=f[8]+'.'+f[10],latitude=f[4],longitude=f[5]))
   except Exception as exc:self.place_errors.append('GeoNames towns: '+str(exc))
   for r in geo:
    for n in {canon(r['name']),*[canon(x) for x in r['aliases']]}:
     if n:self.geo_by_name[n].append(r)
   try:
    self.interval_response=self.fetch('macrostrat','https://macrostrat.org/api/v2/defs/intervals?all')
    for r in self.ext['macro_candidates'](self.interval_response['payload'],self.interval_response['request_url']):self.interval_names[canon(r['name'])].append(r)
   except Exception as exc:self.place_errors.append('Macrostrat intervals: '+str(exc))
 def geo_source(self,c):
  if c['level']=='country':return self.country
  if c['level']=='first-level region':return self.admin
  return dict(request_url=self.citymeta['url'],retrieved_at_utc=self.citymeta['retrieved_at_utc'])
 def resolve(self,key,group):
  kind,name=key;e=max(group,key=lambda e:len(self.valid_anchors(e)));anchors=unique([a for e in group for a in self.valid_anchors(e)])
  row=dict(kind=kind,name=e['name'],source_ids=sorted({e['id'] for e in group}),anchors=anchors,source_anchors=unique([a for e in group for a in e['anchors']]),matched=[],errors=[],status='hard_unresolved',reason='No unique external identity established')
  if not anchors:row.update(status='stale_evidence',reason='No exact active-edition transcript evidence');return row
  if name in self.paleo:
   row.update(status='applied',target_kind='place',target_name=e['name'],reason='Paleogeographic place; retained in Places as instructed by David',confirmed_by='David');return row
  if name in ['saltville','saltville, virginia']:
   self.ensure_places()
   c=[r for r in self.geo_by_name['saltville'] if r['country_code']=='US' and r['admin_code']=='US.VA']
   row.update(status='applied',target_kind='place',target_name='Saltville, Virginia',reason='Location confirmed by David',confirmed_by='David')
   if len(c)==1:row['matched']=[record('geonames',dict(c[0],url='https://www.geonames.org/'+c[0]['id']+'/'),self.geo_source(c[0]))]
   return row
  if kind=='fossil':
   query=self.corrections.get(name,e['name']);selected=[]
   try:
    url=self.pb['query_url']({'name':query});d=self.fetch('pbdb',url);payload=d['payload']
    if payload.get('errors') or not isinstance(payload.get('records'),list):raise ValueError('Invalid PBDB response')
    candidates=[self.pb['metadata'](c,query) for c in payload['records']];exact=[c for c in candidates if canon(c['name'])==canon(query)]
    identities={c['accepted_id'] or c['taxon_id'] for c in exact}
    if len(identities)==1 and exact:
     c=exact[0];row['matched'].append(record('pbdb',c,d));selected.append(c['accepted_name'] or c['name'])
   except Exception as ex:row['errors'].append('PBDB: '+str(ex))
   try:
    url=self.ext['query_url']('col',{'name':query},self.config['col_release']);d=self.fetch('col',url);cs=self.ext['col_candidates'](d['payload'],self.config['col_release'])
    cs=[c for c in cs if canon(c['name'])==canon(query) and c.get('service_match_type') not in ['higherrank','alternative'] and c.get('status') in ['accepted','synonym']]
    if len(cs)==1 and cs[0].get('accepted_name'):
     c=cs[0];row['matched'].append(record('col',c,d));selected.append(c['accepted_name'])
   except Exception as ex:row['errors'].append('CoL: '+str(ex))
   if selected and len({canon(n) for n in selected})==1:
    target=selected[0] if len({m['provider'] for m in row['matched']})>1 or canon(selected[0])==canon(query) else query
    row.update(status='applied',target_name=target,reason='Unique exact scientific-name identity; accepted-name change requires agreement across both taxonomy sources')
   elif selected:row['reason']='External sources disagree on accepted name; original heading retained'
  elif kind=='place':
   self.ensure_places()
   row['errors'].extend(self.place_errors)
   # Geological intervals stay in the existing Places category.
   cs=self.interval_names.get(name,[])
   if cs:
    ids={(c['base_age_ma'],c['top_age_ma']) for c in cs}
    if len(ids)==1:row.update(status='applied',reason='Exact geological interval; retained in existing Places category',matched=[record('macrostrat',cs[0],self.interval_response)])
   else:
    cs=self.geo_by_name.get(name,[])
    countries=[c for c in cs if c['level']=='country']
    if len(countries)==1 and any(e.get('subtype')=='country' for e in group):cs=countries
    if len(cs)>1:
     # Require an explicit geographic qualifier, not merely the most populous town.
     context=' '.join(a['passage_text'] for a in anchors)
     hints=[]
     for c in cs:
      code=c['country_code'];country_name=next((r['name'] for r in self.geo_by_name.get(canon(code),[]) if r['level']=='country'),None)
      if country_name and canon(country_name)!=name and re.search(r'\b'+re.escape(country_name)+r'\b',context,re.I):hints.append(c)
     if len(hints)==1:cs=hints
    if len(cs)==1:
     c=dict(cs[0],url='https://www.geonames.org/'+cs[0]['id']+'/');row.update(status='applied',reason='Unique exact geographic name with available qualifiers',matched=[record('geonames',c,self.geo_source(c))])
    elif len(cs)>1:row['reason']='Ambiguous geographic name: '+', '.join(c['name']+' ('+c['country_code']+')' for c in cs[:8])
    elif re.search(r'\b(formation|group|limestone|sandstone|shale|supergroup)\b',name):
     q=re.sub(r'\b(formation|group|limestone|sandstone|shale|supergroup)\b','',e['name'],flags=re.I).strip()
     try:
      url=self.ext['query_url']('macrostrat',{'name':q,'kind':'strat'});d=self.fetch('macrostrat',url);cs=self.ext['macro_candidates'](d['payload'],url)
      exact=[c for c in cs if canon(c['name'])==name]
      # Stratigraphic homonyms require location metadata: even a sole text hit is insufficient.
      row['reason']='Stratigraphic identity needs geographic correlation; '+str(len(exact))+' exact source records'
      row['candidates']=exact[:5]
     except Exception as ex:row['errors'].append('Macrostrat: '+str(ex))
  elif kind in ['paper','article']:
   try:row.update(resolve_publication(self,group,anchors))
   except Exception as ex:row['errors'].append('Crossref: '+str(ex))
  elif kind=='author':row['reason']='Person identity/authorship not established by a specific matched publication'
  if row['errors'] and row['status']!='applied':
   if all('Invalid or wildcard taxon name' in x for x in row['errors']):
    row['reason']='Indexed wording is not a scientific-name query';row['errors']=[]
   else:row['status']='lookup_error'
  return row

def reconcile_authors(results):
 authors=collections.defaultdict(list)
 for row in results:
  if row['status']!='applied':continue
  for m in row['matched']:
   if m['provider']=='crossref':
    for a in m['record']['authors']:
     n=(a.get('given','')+' '+a.get('family','')).strip() or a.get('name','')
     if n:authors[canon(n)].append((a,m))
 for row in results:
  if row['kind']=='author' and canon(row['name']) in authors:
   matches=authors[canon(row['name'])]
   if len({(a.get('orcid',''),canon(a.get('given','')+' '+a.get('family',''))) for a,m in matches})==1:
    row.update(status='applied',reason='Exact named author of a resolved publication',matched=[m for a,m in matches])

def confirmation_evidence(entry):
 return [{k:a.get(k) for k in ['guid','edition','passage_id','passage_text','quote']} for a in entry.get('anchors',[])]

def externally_confirmed(entry):
 try:marker=json.loads((entry.get('details') or {}).get('external_confirmation','{}'))
 except (TypeError,ValueError):return False
 return (isinstance(marker,dict) and marker.get('status')=='confirmed' and marker.get('name')==entry['name'] and marker.get('kind')==entry['kind'] and isinstance(marker.get('sources'),list) and bool(marker['sources']) and all(s in ['pbdb','col','crossref','macrostrat','geonames'] for s in marker['sources']) and isinstance(marker.get('evidence'),list) and bool(marker['evidence']) and all(a in confirmation_evidence(entry) for a in marker['evidence']))

METADATA_DEFAULTS=dict(name='',kind='',review='suggested',aliases=[],subtype='',year=None,publication='',doi='',url='',link_verified=False,author_ids=[],note='')
def metadata_snapshot(entry):return {k:entry.get(k,default) for k,default in METADATA_DEFAULTS.items()}

def apply_document(document,results,policy):
 original={e['id']:metadata_snapshot(e) for e in document['entries'] if active(e)}
 confirmations={}
 d=copy.deepcopy(document);bykey={(r['kind'],canon(r['name'])):r for r in results};changes=[];merges=[]
 for e in d['entries']:
  if not active(e):continue
  row=bykey.get((e['kind'],canon(e['name'])))
  if row is None:continue
  if row['status']!='applied' or not policy.valid_anchors(e):
   if not row.get('errors') and e.get('details'):e['details'].pop('external_confirmation',None)
   if e['kind'] in ['paper','article'] and row.get('candidates'):
    details=e.setdefault('details',{}) or {};e['details']=details
    details['bibliography']=json.dumps(dict(status='unconfirmed_candidates',candidates=row['candidates']),ensure_ascii=False)
   continue
  old=e['name']
  if not (e['kind'] in ['paper','article'] and e.get('review')=='confirmed'):e['name']=row.get('target_name',old)
  e['kind']=row.get('target_kind',e['kind'])
  if old!=e['name']:e['aliases']=unique([*e.get('aliases',[]),old])
  details=e.get('details') or {};sources=details.get('sources',[]);paragraphs=[]
  for match in row['matched']:
   c=match['record'];url=c.get('url','');provider=match['provider']
   if url:sources.append(dict(url=url,label={'pbdb':'Paleobiology Database','col':'Catalogue of Life '+str(policy.config['col_release']),'geonames':'GeoNames — CC-BY','macrostrat':'Macrostrat — CC-BY 4.0','crossref':'Crossref'}[provider]))
   paragraphs.append(provider+': '+json.dumps({k:v for k,v in c.items() if k not in ['raw_record','review_status','issues']},ensure_ascii=False)+'. Retrieved '+match['retrieved_at_utc'])
   if provider=='crossref' and e['kind'] in ['paper','article']:
    e.update(doi=c['doi'],url=c['url'],link_verified=True,publication=c['journal'] or c['publisher'])
    dates=valid_dates(c)
    if dates:e['year']=min(dates).year
    if e.get('review')=='suggested' and c.get('title'):
     if e['name']!=c['title']:e['aliases']=unique(e.get('aliases',[])+[e['name']])
     e['name']=c['title']
    details['bibliography']=json.dumps(dict(c,status='source_confirmed',match_evidence=match.get('match_evidence',{})),ensure_ascii=False)
    for extra in match.get('match_evidence',{}).get('corroborating_sources',[]):
     sources.append(dict(url=extra,label='Publication identity corroboration'))
  if row['matched']:
   confirmations[e['id']]=unique([match['provider'] for match in row['matched']])
  details['sources']=unique(sources)
  description=details.get('description','');details['description']='\n\n'.join(unique([s for s in description.split('\n\n') if s]+paragraphs))
  note='Automatic external-source enrichment authorised by David, 4 November 2026. '+row['reason']+'. Transcript wording retained.'
  details['editorial_note']='\n'.join(unique([*details.get('editorial_note','').splitlines(),note]));e['details']=details
  # A database identity is not human review. Preserve existing review state except explicit user confirmations.
  if row.get('confirmed_by')=='David':e['review']='confirmed'
  changes.append(dict(path='sidecar',id=e['id'],old_name=old,name=e['name'],kind=e['kind']))
 previous_ids={e['id'] for e in d['entries']}
 blacklist=load_blacklist(policy.root)
 attach_authors(d,confirmations,policy.valid_anchors,lambda e:blocked(e,blacklist))
 changes.extend(dict(path='sidecar',id=e['id'],name=e['name'],kind='author',created=True) for e in d['entries'] if e['id'] not in previous_ids)
 # Exact category/name duplicates only; include all anchored evidence and redirect author links.
 groups=collections.defaultdict(list)
 for e in d['entries']:
  if active(e):groups[(e['kind'],canon(e['name']))].append(e)
 redirects={}
 for key,group in groups.items():
  if len(group)<2:continue
  group.sort(key=lambda e:(e.get('review')!='confirmed',e['id']));target=group[0]
  for variant in group[1:]:
   confirmations[target['id']]=unique(confirmations.get(target['id'],[])+confirmations.get(variant['id'],[]))
   target['anchors']=unique(target['anchors']+variant['anchors']);target['aliases']=unique(target.get('aliases',[])+variant.get('aliases',[])+[variant['name']])
   target['variant_ids']=unique(target.get('variant_ids',[])+[variant['id']]+variant.get('variant_ids',[]))
   target['author_ids']=unique(target.get('author_ids',[])+variant.get('author_ids',[]))
   td=target.get('details') or {};target['details']=td;vd=variant.get('details') or {}
   td['sources']=unique(td.get('sources',[])+vd.get('sources',[]))
   td['normalizations']=unique(td.get('normalizations',[])+vd.get('normalizations',[]))
   td['spoken']=unique(td.get('spoken',[])+vd.get('spoken',[]))
   td['description']='\n\n'.join(unique([x for x in (td.get('description','')+'\n\n'+vd.get('description','')).split('\n\n') if x]))
   variant['review']='rejected';variant['note']=variant.get('note','')+'\nDuplicate merged into '+target['id']+' during authorised external enrichment.';redirects[variant['id']]=target['id'];merges.append(dict(path='sidecar',source=variant['id'],target=target['id']))
 for e in d['entries']:
  if active(e):e['author_ids']=unique([redirects.get(i,i) for i in e.get('author_ids',[])])

 for e in d['entries']:
  if active(e) and confirmations.get(e['id']):
   details=e.get('details') or {};e['details']=details
   details['external_confirmation']=json.dumps(dict(status='confirmed',name=e['name'],kind=e['kind'],sources=confirmations[e['id']],evidence=confirmation_evidence(dict(anchors=policy.valid_anchors(e)))[:1]),ensure_ascii=False)
  before=original.get(e['id'])
  if before is None or before==metadata_snapshot(e):continue
  details=e.get('details') or {};e['details']=details
  try:prior=json.loads(details.get('refinement_source','{}'))
  except (TypeError,ValueError):prior={}
  chain=prior if isinstance(prior,list) else [prior]
  chain=unique([v for v in chain if isinstance(v,dict) and set(v)==set(METADATA_DEFAULTS)]+[before])
  details['refinement_source']=json.dumps(chain[0] if len(chain)==1 else chain,ensure_ascii=False)
 d,_=apply_blacklist(d,load_blacklist(policy.root))
 return d,changes,merges

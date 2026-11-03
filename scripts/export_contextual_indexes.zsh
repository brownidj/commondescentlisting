#!/bin/zsh
# Compile completed cached extractions into the offline app's index asset.
set -euo pipefail
index_project="${0:A:h:h}"
exec "${INDEX_TRIAL_PYTHON:-python3}" - "$index_project" <<'PY_EXPORT'
from pathlib import Path
import hashlib,json,re,sys
project=Path(sys.argv[1]);out=project/'outputs/indexing-app'
paths=[project/'outputs/indexing-trial/episode-208-karoo']
paths+=sorted(p.parent for p in out.glob('*/proposed-index.json'))
def load(p): return json.loads(p.read_text())
def pretty(v): return json.dumps(v,ensure_ascii=False,indent=2) if v else ''
def canonical(v): return re.sub(r'\s+',' ',v.casefold()).strip()
def unique(rows): return list({json.dumps(r,sort_keys=True,ensure_ascii=False):r for r in rows}.values())
entries={};coverage=[]
for path in paths:
    source=load(path/'source_snapshot.json');index=load(path/'proposed-index.json');config=load(path/'config.json')
    if index['source_sha256']!=hashlib.sha256(json.dumps(source,sort_keys=True).encode()).hexdigest():
        raise SystemExit('Index source snapshot mismatch: '+str(path))
    prepared=load(path/'prepared.json');usage=load(path/'usage.json')
    if len(usage['requests'])!=prepared['chunks'] or any(r['status']!='completed' for r in usage['requests']):
        raise SystemExit('Incomplete extraction: '+str(path))
    cues={c['id']:c for c in source['passages']};guid=source['episode_guid']
    coverage.append(dict(guid=guid,title=source['episode_title'],edition=source['edition'],passages=len(cues)))
    def key(e):
        pub=e.get('editorial_curation',{}).get('bibliographic_details') or {}
        doi=pub.get('doi') or next((p['doi'] for p in e['publication_proposals'] if p.get('doi')),None)
        identity=[e['kind'],canonical(e['subtype']),canonical(e['name'])]
        if e['kind'] in ['paper','article']: identity=[e['kind'],doi] if doi else identity+[guid,e['id']]
        return 'api:'+hashlib.sha256(json.dumps(identity).encode()).hexdigest()[:24]
    authors={}
    def author_signature(name):
        return ' '.join(w for w in re.findall(r'[^\W\d_]+',name.casefold()) if len(w)>1)
    for e in index['entries']:
        if e['kind']!='author': continue
        for name in [e['name'],*e['spoken_names'],*e['observed_forms']]:
            for alias in [canonical(name),author_signature(name)]:
                authors.setdefault(alias,set()).add(key(e))
    def author_link(name):
        ids=authors.get(canonical(name)) or authors.get(author_signature(name)) or set()
        return next(iter(ids)) if len(ids)==1 else None
    for e in index['entries']:
        if not e['occurrences']: continue
        curated=e.get('editorial_curation',{});pub=curated.get('bibliographic_details') or next(iter(e['publication_proposals']),{})
        name=e['name']
        if e['kind'] in ['paper','article'] and (name.startswith('Untitled ') or not curated):
            author=', '.join(pub.get('authors',[]));date=pub.get('date_text') or pub.get('year')
            subject=pub.get('title') or ' '.join(e['qualifiers']).split(';')[0].rstrip('.')
            subject=re.sub(r'^Untitled (?:paper|article)(?: about)?\s*','',subject,flags=re.I)
            subject=subject.replace('Karu','Karoo')
            name=', '.join(str(v) for v in [author,date,subject] if v)
        sources=[dict(url=s['url'],label=', '.join(s['fields'])) for s in curated.get('sources',[]) if s.get('url')]
        details=dict(spoken=e['spoken_names'],description='\n'.join(e['qualifiers']),confidence=e['confidence'],
            normalizations=e['normalization_proposals']+[n['reason'] for n in e.get('normalization_warnings',[])],
            editorial_note=curated.get('note','Contextual API suggestion. Names and classifications need review; reference labels describe the known subject, not an invented formal title.'),
            bibliography=pretty(curated.get('bibliographic_details')),original_publication=pretty(e['publication_proposals']),sources=sources,model=config['model'])
        anchors=[]
        for occurrence in e['occurrences']:
            cue=cues[occurrence['passage_id']]
            if occurrence['quote'] not in cue['text'] or occurrence['edition']!=source['edition'] or occurrence['audio_identity']!=source['audio_identity']:
                raise SystemExit('Invalid source evidence for '+e['id'])
            anchors.append(dict(guid=guid,quote=occurrence['quote'],passage_id=cue['id'],edition=source['edition'],passage_text=cue['text']))
        dates=pub.get('publication_dates',{});year=pub.get('year')
        if not year and dates: year=int(next(iter(dates.values()))[:4])
        ident=key(e)
        row=dict(id=ident,kind=e['kind'],name=name,review='suggested',aliases=unique(e['observed_forms']),subtype=e['subtype'],
            year=year,publication=pub.get('journal_or_publisher') or '',doi=pub.get('doi') or '',url=pub.get('url') or '',
            link_verified=bool(curated and pub.get('url')),author_ids=unique([author_id for n in pub.get('authors',[]) if (author_id:=author_link(n))]),
            anchors=anchors,note='Contextual index suggestion from '+source['episode_title']+'.',details=details)
        if ident in entries:
            prior=entries[ident];prior['anchors']=unique(prior['anchors']+anchors);prior['aliases']=unique(prior['aliases']+row['aliases'])
            prior['details']['description']='\n'.join(unique([prior['details']['description'],details['description']]))
            for field in ['spoken','normalizations','sources']: prior['details'][field]=unique(prior['details'][field]+details[field])
            prior['author_ids']=unique(prior['author_ids']+row['author_ids'])
        else: entries[ident]=row
for e in entries.values():
    e['author_ids']=[a for a in e['author_ids'] if a in entries and entries[a]['kind']=='author']
asset=dict(schema_version=1,entries=sorted(entries.values(),key=lambda e:(e['kind'],e['name'].casefold())))
target=project/'flutter_app/assets/data/contextual_indexes.json'
target.write_text(pretty(asset)+'\n')
(out/'contextual-indexes.json').write_text(pretty(asset)+'\n')
(out/'coverage.json').write_text(pretty(dict(episodes=coverage,entries=len(entries)))+'\n')
print('Exported',len(entries),'entries from',len(coverage),'completed transcript indexes.')
PY_EXPORT

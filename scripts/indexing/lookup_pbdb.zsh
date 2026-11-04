#!/bin/zsh
# Optional PBDB taxonomy suggestions; preserves index decisions and literal text.
set -euo pipefail
pbdb_project="${0:A:h:h:h}"
exec python3 - "$pbdb_project" "$@" <<'PY_PBDB'
from pathlib import Path
import argparse,datetime,hashlib,html,json,re,sys,time,urllib.parse,urllib.request,urllib.error

def sha(data):return hashlib.sha256(data).hexdigest()
def load(path):return json.loads(path.read_text())
def write(path,data):
    path.parent.mkdir(parents=True,exist_ok=True);tmp=path.with_suffix(path.suffix+'.pending')
    tmp.write_text(json.dumps(data,indent=2,ensure_ascii=False)+'\n');tmp.replace(path)
def canon(value):return ' '.join(value.casefold().split())
def query_url(query):
    name=query.get('name','').strip()
    # Deliberate scientific/common-name queries only; no wildcard expansions.
    if '_' in name or '%' in name or not 3<=len(name)<=200 or not re.fullmatch(r"[\w .()’'–-]+",name):raise ValueError('Invalid or wildcard taxon name')
    return 'https://paleobiodb.org/data1.2/taxa/list.json?'+urllib.parse.urlencode(dict(name=name,vocab='pbdb',show='attr,class,app',taxon_status='all',limit=5))
def metadata(record,query_name):
    ident=str(record.get('taxon_no',''));accepted=str(record.get('accepted_no',''))
    if not ident.isdigit() or not record.get('taxon_name'):raise ValueError('Invalid PBDB taxon record')
    return dict(taxon_id=ident,concept_id=str(record.get('orig_no','')),name=record['taxon_name'],rank=record.get('taxon_rank',''),
        attribution=record.get('taxon_attr',''),accepted_id=accepted,accepted_name=record.get('accepted_name',''),accepted_rank=record.get('accepted_rank',''),
        exact_query_name=canon(record['taxon_name'])==canon(query_name),
        nomenclatural_note=record.get('difference',record.get('taxon_status','')),
        classification={key:record[key] for key in ['phylum','class','order','family','genus','subgenus'] if key in record and not str(record[key]).startswith('NO_')},
        extant_indicator=record.get('is_extant','not supplied'),
        recorded_occurrence_range={key:record[key] for key in ['firstapp_max_ma','firstapp_min_ma','lastapp_max_ma','lastapp_min_ma','early_interval','late_interval'] if key in record},
        occurrence_count=record.get('n_occs'),reference_id=str(record.get('reference_no','')),
        url='https://paleobiodb.org/classic/basicTaxonInfo?taxon_no='+ident,
        accepted_url='https://paleobiodb.org/classic/basicTaxonInfo?taxon_no='+accepted if accepted.isdigit() else '',
        review_status='requires_review',mention_confirmed=False)
def main():
    project=Path(sys.argv[1]);p=argparse.ArgumentParser()
    for key in ['index','baseline','plan','output']:p.add_argument('--'+key,type=Path,required=True)
    p.add_argument('--online',action='store_true');p.add_argument('--max-requests',type=int,default=20)
    a=p.parse_args(sys.argv[2:]);doc=load(a.index);base=load(a.baseline);plan=load(a.plan)
    if doc.get('schema_version')!=1 or plan.get('schema_version')!=1 or not 1<=a.max_requests<=50:raise ValueError('Invalid plan/schema/request limit')
    if sha(a.index.read_bytes())!=plan['index_sha256'] or sha(a.baseline.read_bytes())!=plan['baseline_sha256'] or base['episode_guid']!=plan['episode_guid']:
        raise ValueError('Stale or mismatched index/baseline plan')
    entries={e['id']:e for e in doc['entries'] if e['kind']=='fossil' and e.get('review')!='rejected' and not e.get('deleted')}
    passages={c['id']:c['text'] for c in base['segments']};queries=plan['queries']
    if not isinstance(queries,list) or not queries or len(queries)>a.max_requests or len({q['id'] for q in queries})!=len(queries):raise ValueError('Invalid, duplicate or excessive queries')
    prepared=[]
    for q in queries:
        if not isinstance(q.get('source_ids'),list) or not q['source_ids']:raise ValueError('A query needs active Taxonomy source IDs')
        sources=[entries[ident] for ident in q['source_ids']]
        for e in sources:
            if not e['anchors']:raise ValueError('Missing literal evidence')
            for anchor in e['anchors']:
                if anchor['guid']!=plan['episode_guid'] or anchor.get('edition')!=plan['edition'] or anchor.get('passage_text')!=passages.get(anchor.get('passage_id')) or anchor['quote'] not in anchor['passage_text']:
                    raise ValueError('Stale taxonomy evidence')
        prepared.append((q,sources,query_url(q)))
    cache=project/'work/pbdb-cache';results=[];sent=0;last=0;halt=None
    for q,sources,url in prepared:
        row=dict(id=q['id'],query=q,request_url=url,sources=[dict(id=e['id'],name=e['name'],review=e.get('review','suggested'),anchors=e['anchors']) for e in sources],candidates=[],published_index_modified=False)
        path=cache/(sha(url.encode())+'.json')
        try:
            if path.exists():
                response=load(path)
                if response['request_url']!=url:raise ValueError('Invalid PBDB cache identity')
                row['cache_hit']=True
            else:
                if not a.online:raise ValueError('No cached response; --online explicitly enables PBDB requests')
                if halt:raise ValueError(halt)
                time.sleep(max(0,1-(time.monotonic()-last)));last=time.monotonic();sent+=1
                request=urllib.request.Request(url,headers={'User-Agent':'CommonDescentListing-Taxonomy/0.1','Accept':'application/json'})
                with urllib.request.urlopen(request,timeout=20) as r:
                    body=r.read(3_000_001)
                    if len(body)>3_000_000:raise ValueError('PBDB response too large')
                    response=dict(request_url=url,retrieved_at_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),payload=json.loads(body))
                if response['payload'].get('errors') or not isinstance(response['payload'].get('records'),list):raise ValueError('PBDB error: '+str(response['payload'].get('errors','invalid records')))
                write(path,response);row['cache_hit']=False
            payload=response['payload']
            if payload.get('errors') or not isinstance(payload.get('records'),list):raise ValueError('PBDB cache has error/invalid records')
            candidates=[metadata(item,q['name']) for item in payload['records']]
            for candidate in candidates:
                candidate['exact_index_name']=any(canon(candidate['name'])==canon(e['name']) for e in sources)
            row.update(status='candidates' if candidates else 'unresolved',candidates=candidates,retrieved_at_utc=response['retrieved_at_utc'],service_warnings=payload.get('warnings',[]))
        except urllib.error.HTTPError as e:
            if e.code in (429,503):halt=f'PBDB backoff (HTTP {e.code}); remaining uncached requests stopped. Retry later.'
            row.update(status='error',error=halt or f'PBDB HTTP {e.code}')
        except (ValueError,KeyError,urllib.error.URLError,TimeoutError) as e:row.update(status='error',error=str(e))
        results.append(row);print(q['id'],row['status'],len(row['candidates']),flush=True)
    counts={key:sum(r['status']==key for r in results) for key in ['candidates','unresolved','error']}
    report=dict(schema_version=1,source='Paleobiology Database data service 1.2',episode_guid=plan['episode_guid'],edition=plan['edition'],
        index_sha256=plan['index_sha256'],baseline_sha256=plan['baseline_sha256'],requests_sent=sent,paid_api_calls=0,published_index_modified=False,
        outcomes=counts,results=results)
    write(a.output/'results.json',report)
    esc=lambda s:html.escape(str(s));sections=[]
    for row in results:
        content='<section><h2>'+esc(row['query']['name'])+'</h2><p><strong>'+esc(row['status'])+'</strong> · '+esc(row['id'])+'</p><p>'+esc(row['query'].get('note',''))+'</p>'
        for source in row['sources']:
            content+='<details open><summary>Indexed wording: '+esc(source['name'])+'</summary>'
            for anchor in source['anchors'][:4]:content+='<blockquote>Passage '+str(anchor['passage_id'])+': '+esc(anchor['passage_text'])+'</blockquote>'
            if len(source['anchors'])>4:content+='<p>More anchors preserved in results.json.</p>'
            content+='</details>'
        if row.get('error'):content+='<p>'+esc(row['error'])+'</p>'
        if row.get('service_warnings'):content+='<p>PBDB warnings: '+esc(json.dumps(row['service_warnings']))+'</p>'
        if row['status']=='unresolved':content+='<p>No matching PBDB record returned. This does not prove the indexed name is invalid or non-taxonomic.</p>'
        for item in row['candidates']:
            content+='<article><h3>'+esc(item['name'])+'</h3><p>'+esc(item['rank'])+' · '+esc(item['attribution'])+' · taxon '+esc(item['taxon_id'])+'</p><p>PBDB accepted name: '+esc(item['accepted_name'])+' ('+esc(item['accepted_id'])+')</p><p>Exact queried name: '+esc(item['exact_query_name'])+' · Exact indexed name: '+esc(item['exact_index_name'])+' · Requires review</p><p>Classification: '+esc(json.dumps(item['classification'],ensure_ascii=False))+'</p><p>PBDB extant indicator: '+esc(item['extant_indicator'])+'</p><p>Recorded occurrence range (Ma): '+esc(json.dumps(item['recorded_occurrence_range']))+'</p><p>Recorded occurrences: '+esc(item['occurrence_count'])+' · Reference ID: '+esc(item['reference_id'])+'</p><a href="'+esc(item['url'])+'">PBDB source record</a></article>'
        sections.append(content+'</section>')
    page='<!doctype html><html lang="en"><meta charset="utf-8"><title>PBDB Taxonomy review</title><style>body{font:16px system-ui;max-width:1100px;margin:32px auto;background:#f4faf8;color:#18392e}article{background:white;padding:16px;margin:14px 0;border:1px solid #b8ccc2;border-radius:8px}section{margin:35px 0}blockquote{border-left:4px solid #8ab29f;padding:10px}p{line-height:1.5}summary{cursor:pointer}</style><h1>Paleobiology Database — Taxonomy review</h1><p>All ranks stay in the single Taxonomy index. Database name matches are not confirmed transcript identifications. Common-name and proposed-spelling queries are explicitly marked. No-match is unresolved, not rejection. Occurrence ages describe PBDB records, not necessarily a taxon’s complete range.</p><p>'+esc(json.dumps(counts))+'</p>'+''.join(sections)+'</html>'
    (a.output/'review.html').write_text(page);print('Report:',a.output/'review.html','HTTP requests:',sent)
if __name__=='__main__':main()
PY_PBDB

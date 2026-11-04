#!/bin/zsh
# Optional, cached metadata lookup; never changes an index or confirms a match.
set -euo pipefail
crossref_project="${0:A:h:h:h}"
exec python3 - "$crossref_project" "$@" <<'PY_CROSSREF'
from pathlib import Path
import argparse,datetime,hashlib,html,json,re,sys,time,urllib.parse,urllib.request,urllib.error

def sha(data): return hashlib.sha256(data).hexdigest()
def load(path): return json.loads(path.read_text())
def write(path,data):
    path.parent.mkdir(parents=True,exist_ok=True)
    tmp=path.with_suffix(path.suffix+'.pending');tmp.write_text(json.dumps(data,indent=2,ensure_ascii=False)+'\n');tmp.replace(path)
def now(): return datetime.datetime.now(datetime.timezone.utc).isoformat()
def query_url(query,cutoff,mailto=''):
    doi=query.get('doi','').strip()
    if doi:
        if not re.fullmatch(r'10\.\d{4,9}/\S+',doi):raise ValueError('Invalid DOI')
        url='https://api.crossref.org/works/'+urllib.parse.quote(doi,safe='')
        return url+('?' + urllib.parse.urlencode({'mailto':mailto}) if mailto else '')
    text=query.get('query','').strip()
    if not 8<=len(text)<=1000:raise ValueError('Supply a specific bibliographic query (8–1000 characters)')
    rows=query.get('rows',3)
    if type(rows) is not int or not 1<=rows<=20:raise ValueError('Crossref rows must be 1–20')
    params={'query.bibliographic':text,'rows':rows}
    if query.get('author'):params['query.author']=query['author']
    strict=query.get('strict_publication_cutoff',False)
    if not isinstance(strict,bool):raise ValueError('strict_publication_cutoff must be boolean')
    if cutoff:
        datetime.date.fromisoformat(cutoff)
        if strict:params['filter']='until-pub-date:'+cutoff
    if mailto:params['mailto']=mailto
    return 'https://api.crossref.org/works?'+urllib.parse.urlencode(params)
def metadata(item,cutoff=''):
    doi=item.get('DOI','')
    dates={k:item[k].get('date-parts',[]) for k in ['published','published-online','published-print','issued'] if isinstance(item.get(k),dict)}
    known=[]
    for lists in dates.values():
        for parts in lists:
            try:known.append(datetime.date(*(parts+[1,1])[:3]))
            except (TypeError,ValueError):pass
    date_note='Crossref dates are after the episode; check online-first or preprint publication. Candidate retained for review.' if cutoff and known and min(known)>datetime.date.fromisoformat(cutoff) else ''
    return dict(title='; '.join(item.get('title',[])),
        authors=[dict(given=a.get('given',''),family=a.get('family',''),name=a.get('name',''),orcid=a.get('ORCID','')) for a in item.get('author',[])],
        dates=dates,publication_date_note=date_note,
        journal='; '.join(item.get('container-title',[])),publisher=item.get('publisher',''),doi=doi,
        url='https://doi.org/'+urllib.parse.quote(doi,safe='/') if doi else '',
        crossref_type=item.get('type',''),crossref_relevance_score=item.get('score'),
        status='candidate_requires_review')
def main():
    project=Path(sys.argv[1]);p=argparse.ArgumentParser()
    for name in ['index','baseline','plan','output']:p.add_argument('--'+name,type=Path,required=True)
    p.add_argument('--online',action='store_true',help='Explicitly allow Crossref HTTP requests; default uses cache only')
    p.add_argument('--max-requests',type=int,default=10);p.add_argument('--mailto',default='')
    a=p.parse_args(sys.argv[2:]);index=load(a.index);base=load(a.baseline);plan=load(a.plan)
    if plan.get('schema_version')!=1 or index.get('schema_version')!=1 or not 1<=a.max_requests<=50:raise ValueError('Invalid lookup plan or request limit')
    if plan['index_sha256']!=sha(a.index.read_bytes()) or plan['baseline_sha256']!=sha(a.baseline.read_bytes()) or plan['episode_guid']!=base['episode_guid']:
        raise ValueError('Query plan does not match this episode/index/baseline')
    sources={e['id']:e for e in index['entries'] if e['kind'] in ('paper','article') and not e.get('deleted') and e.get('review')!='rejected'}
    sources.update({g['id']:g for g in index.get('unidentified_reference_mentions',[])})
    passages={p['id']:p for p in base['segments']};queries=plan['queries']
    if not isinstance(queries,list) or not queries or len(queries)>a.max_requests or len({q['id'] for q in queries})!=len(queries):
        raise ValueError('Invalid, duplicate or excessive query plan')
    prepared=[]
    # Validate every reference before performing any network requests.
    for q in queries:
        source=sources[q['source_id']]
        for anchor in source['anchors']:
            if anchor['guid']!=base['episode_guid'] or anchor['edition']!=plan['edition'] or anchor['passage_text']!=passages[anchor['passage_id']]['text'] or anchor['quote'] not in anchor['passage_text']:
                raise ValueError('Stale source evidence')
        context=[passages[pid] for pid in q.get('passage_ids',[])]
        if not source['anchors']:raise ValueError('Missing source evidence')
        prepared.append((q,source,context,query_url(q,plan.get('publication_cutoff',''),a.mailto)))
    cache=project/'work/crossref-cache';sent=0;last=0;results=[];halt=None
    for q,source,context,url in prepared:
        row=dict(id=q['id'],source_id=q['source_id'],query=q,anchors=source['anchors'],context=context,request_url=url,
                 mention_confirmed=False,candidates=[])
        cached=cache/(sha(url.encode())+'.json')
        try:
            if cached.exists():
                response=load(cached)
                if response['request_url']!=url:raise ValueError('Invalid Crossref cache identity')
                row['cache_hit']=True
            else:
                if not a.online:raise ValueError('Not cached; pass --online to permit a lookup')
                if halt:raise ValueError(halt)
                time.sleep(max(0,1-(time.monotonic()-last)))
                request=urllib.request.Request(url,headers={'User-Agent':'CommonDescentListing-Crossref/0.1','Accept':'application/json'})
                sent+=1;last=time.monotonic()
                with urllib.request.urlopen(request,timeout=20) as r:
                    payload=r.read(5_000_001)
                    if len(payload)>5_000_000:raise ValueError('Crossref response too large')
                    response=dict(request_url=url,retrieved_at_utc=now(),payload=json.loads(payload))
                if response['payload'].get('status')!='ok':raise ValueError('Crossref response not successful')
                write(cached,response);row['cache_hit']=False
            message=response['payload']['message']
            items=[message] if q.get('doi') else message['items']
            row.update(status='candidates' if items else 'no_results',retrieved_at_utc=response['retrieved_at_utc'],candidates=[metadata(x,plan.get('publication_cutoff','')) for x in items])
        except urllib.error.HTTPError as e:
            if e.code in (429,503):halt=f'Crossref requested backoff (HTTP {e.code}); remaining uncached requests stopped. Retry later.'
            row.update(status='error',error=halt or f'Crossref HTTP {e.code}')
        except (ValueError,KeyError,urllib.error.URLError,TimeoutError) as e:row.update(status='error',error=str(e))
        results.append(row);print(q['id'],row['status'],len(row['candidates']),flush=True)
    report=dict(schema_version=1,episode_publication_date=plan.get('publication_cutoff',''),date_policy='advisory unless strict_publication_cutoff is explicitly true',episode_guid=plan['episode_guid'],edition=plan['edition'],index_sha256=plan['index_sha256'],
        baseline_sha256=plan['baseline_sha256'],created_at_utc=now(),requests_sent=sent,paid_api_calls=0,
        source='Crossref REST API',published_index_modified=False,results=results)
    write(a.output/'results.json',report)
    esc=lambda x:html.escape(str(x));sections=[]
    for row in results:
        body='<section><h2>'+esc(row['id'])+'</h2><p><strong>'+esc(row['status'])+' — reference identity unconfirmed</strong></p><p>Analyst query: '+esc(row['query'].get('query',row['query'].get('doi','')))+'</p>'
        if row['query'].get('note'):body+='<p>'+esc(row['query']['note'])+'</p>'
        for anchor in row['anchors']:body+='<blockquote>Passage '+str(anchor['passage_id'])+': '+esc(anchor['passage_text'])+'</blockquote>'
        body+='<details><summary>Additional transcript context</summary>'+''.join('<p>'+str(c['id'])+': '+esc(c['text'])+'</p>' for c in row['context'])+'</details>'
        if row.get('error'):body+='<p>'+esc(row['error'])+'</p>'
        for item in row['candidates']:
            authors='; '.join(x['name'] or (x['given']+' '+x['family']).strip() for x in item['authors'])
            body+='<article><h3>'+esc(item['title'])+'</h3><p>'+esc(authors)+'</p><p>'+esc(item['journal'])+' · '+esc(item['publisher'])+'</p><p>Publication dates: '+esc(json.dumps(item['dates']))+'</p><p>'+esc(item['crossref_type'])+' · Search relevance score: '+esc(item['crossref_relevance_score'])+' (not confidence)</p>'
            if item.get('publication_date_note'):body+='<p><strong>'+esc(item['publication_date_note'])+'</strong></p>'
            if item['doi']:body+='<p><a href="'+esc(item['url'])+'">'+esc(item['doi'])+'</a></p>'
            body+='</article>'
        sections.append(body+'</section>')
    page='<!doctype html><html lang="en"><meta charset="utf-8"><title>Crossref publication review</title><style>body{font:16px system-ui;max-width:1100px;margin:32px auto;background:#f4faf8;color:#18392e}section{margin:30px 0}article{background:white;padding:15px;border:1px solid #b8ccc2;margin:12px 0;border-radius:8px}blockquote{border-left:4px solid #88baa4;padding:12px}p{line-height:1.5}</style><h1>Crossref publication candidates</h1><p>Metadata lookup, not verified identification of a spoken reference. Search scores are relevance rankings, not probabilities. Original evidence and published indexes are unchanged.</p>'+''.join(sections)+'</html>'
    (a.output/'review.html').write_text(page)
    print('Report:',a.output/'review.html','HTTP requests:',sent,flush=True)
if __name__=='__main__':main()
PY_CROSSREF

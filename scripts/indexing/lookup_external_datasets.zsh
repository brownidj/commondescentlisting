#!/bin/zsh
# Optional evidence-bound Catalogue of Life, GeoNames and Macrostrat trials.
set -euo pipefail
external_project="${0:A:h:h:h}"
exec python3 - "$external_project" "$@" <<'PY_EXTERNAL'
from pathlib import Path
import argparse,collections,datetime,hashlib,html,json,sys,time,unicodedata,urllib.parse,urllib.request,urllib.error

def sha(data):return hashlib.sha256(data).hexdigest()
def load(path):return json.loads(path.read_text())
def write(path,data):
    path.parent.mkdir(parents=True,exist_ok=True);tmp=path.with_suffix(path.suffix+'.pending')
    tmp.write_text(json.dumps(data,indent=2,ensure_ascii=False)+'\n');tmp.replace(path)
def canon(text):return ' '.join(''.join(c for c in unicodedata.normalize('NFKD',text.casefold()) if not unicodedata.combining(c)).split())
def query_url(provider,q,dataset=None):
    name=q.get('name','').strip()
    if not 3<=len(name)<=200:raise ValueError('Supply a bounded name query')
    if provider=='col':
        if not str(dataset).isdigit():raise ValueError('Pin a numeric Catalogue of Life release key first')
        return f'https://api.checklistbank.org/dataset/{dataset}/match/nameusage?'+urllib.parse.urlencode({'q':name})
    if provider=='macrostrat':
        route=q.get('kind','strat')
        if route not in ('strat','interval'):raise ValueError('Macrostrat kind must be strat or interval')
        return 'https://macrostrat.org/api/v2/defs/'+('intervals?' if route=='interval' else 'strat_names?')+urllib.parse.urlencode({'name' if route=='interval' else 'strat_name_like':name})
    if provider=='geonames':return 'https://download.geonames.org/export/dump/countryInfo.txt'
    raise ValueError('Unsupported provider')
def col_candidates(payload,dataset):
    if not isinstance(payload,dict):raise ValueError('Invalid CoL response')
    if payload.get('error') or payload.get('errors'):raise ValueError('CoL service error: '+str(payload))
    rows=[]
    if payload.get('usage'):rows.append((payload['usage'],payload.get('match'),payload.get('type')))
    for alternative in payload.get('alternatives',[]) or []:
        rows.append((alternative.get('usage',alternative),False,'alternative'))
    output=[]
    for usage,matched,kind in rows:
        ident=usage.get('id');name=usage.get('name')
        if not ident or not name:continue
        accepted=usage if usage.get('status')=='accepted' else next((r for r in usage.get('classification',[]) if r.get('id')==usage.get('parentId') and r.get('status')=='accepted' and usage.get('status')=='synonym'),{})
        output.append(dict(name=name,id=ident,rank=usage.get('rank'),status=usage.get('status'),authorship=usage.get('authorship'),accepted_name=accepted.get('name'),accepted_id=accepted.get('id'),
            classification=usage.get('classification',[]),service_match=matched,service_match_type=kind,issues=payload.get('issues',{}),
            url=f'https://www.checklistbank.org/dataset/{dataset}/taxon/'+urllib.parse.quote(str(ident),safe=''),
            raw_record=usage,review_status='requires_review'))
    return output

def geo_records(country_text,admin_text):
    output=[]
    for line in country_text.splitlines():
        if not line or line.startswith('#'):continue
        fields=line.split('\t')
        if len(fields)<17 or not fields[16].isdigit():raise ValueError('Invalid GeoNames country extract')
        output.append(dict(id=fields[16],name=fields[4],aliases=[fields[0],fields[1]],level='country',country_code=fields[0],capital=fields[5],continent_code=fields[8]))
    for line in admin_text.splitlines():
        if not line or line.startswith('#'):continue
        fields=line.split('\t')
        if len(fields)!=4 or not fields[3].isdigit():raise ValueError('Invalid GeoNames admin extract')
        output.append(dict(id=fields[3],name=fields[1],aliases=[fields[2]],level='first-level region',country_code=fields[0].split('.')[0],admin_code=fields[0]))
    return output

def geo_matches(records,q):
    name=canon(q['name']);results=[]
    for record in records:
        if q.get('country') and q['country']!=record['country_code']:continue
        words=[canon(record['name']),*[canon(s) for s in record['aliases']]]
        exact=name in words;prefix=record['level']=='first-level region' and len(name)>=4 and any(w.startswith(name+' ') for w in words)
        if exact or prefix:results.append(dict(record,match_type='exact/alias' if exact else 'region name prefix',url='https://www.geonames.org/'+record['id']+'/',review_status='requires_review'))
    return sorted(results,key=lambda r:(r['match_type']!='exact/alias',r['country_code'],r['name']))

def macro_candidates(payload,url):
    success=payload.get('success')
    if not isinstance(success,dict) or not isinstance(success.get('data'),list):raise ValueError('Invalid Macrostrat response or query parameters')
    output=[]
    for record in success['data']:
        name=record.get('strat_name',record.get('name'));ident=record.get('strat_name_id',record.get('int_id'))
        if name is None or ident is None:raise ValueError('Invalid Macrostrat record')
        output.append(dict(name=name,id=ident,kind='geologic interval' if 'int_id' in record else 'stratigraphic name',
            rank=record.get('rank',record.get('int_type')),base_age_ma=record.get('b_age'),top_age_ma=record.get('t_age'),
            license=success.get('license'),references=success.get('refs',{}),raw_record=record,url=url,review_status='requires_review'))
    return output

def main():
    project=Path(sys.argv[1]);p=argparse.ArgumentParser()
    p.add_argument('--provider',choices=['col','geonames','macrostrat'],required=True)
    for name in ['index','baseline','plan','output']:p.add_argument('--'+name,type=Path,required=True)
    p.add_argument('--online',action='store_true');p.add_argument('--max-requests',type=int,default=20)
    a=p.parse_args(sys.argv[2:]);doc=load(a.index);base=load(a.baseline);plan=load(a.plan)
    if doc.get('schema_version')!=1 or plan.get('schema_version')!=1 or plan.get('provider')!=a.provider or not 1<=a.max_requests<=50:raise ValueError('Invalid plan/provider/request limit')
    if sha(a.index.read_bytes())!=plan['index_sha256'] or sha(a.baseline.read_bytes())!=plan['baseline_sha256'] or base['episode_guid']!=plan['episode_guid']:raise ValueError('Stale or mismatched input plan')
    expected='fossil' if a.provider=='col' else 'place'
    entries={e['id']:e for e in doc['entries'] if e['kind']==expected and e.get('review')!='rejected' and not e.get('deleted')}
    passages={c['id']:c['text'] for c in base['segments']};queries=plan['queries'];prepared=[]
    if not queries or len(queries)>50 or len({q['id'] for q in queries})!=len(queries):raise ValueError('Invalid query coverage')
    for q in queries:
        if not q.get('source_ids'):raise ValueError('Query needs active source entries')
        sources=[entries[ident] for ident in q['source_ids']]
        for entry in sources:
            if not entry['anchors']:raise ValueError('Missing transcript anchors')
            for anchor in entry['anchors']:
                if anchor['guid']!=plan['episode_guid'] or anchor.get('edition')!=plan['edition'] or anchor.get('passage_text')!=passages.get(anchor.get('passage_id')) or anchor['quote'] not in anchor['passage_text']:raise ValueError('Stale source evidence')
        prepared.append((q,sources,query_url(a.provider,q,plan.get('dataset_key'))))
    cache=project/'work/external-datasets-cache';sent=0;last=0;halt=None;fetches={};gazetteer=None;results=[]
    def get(url,text=False):
        nonlocal sent,last,halt
        if url in fetches:return fetches[url]
        path=cache/(sha(url.encode())+'.json')
        if path.exists():
            response=load(path)
            if response['request_url']!=url:raise ValueError('Invalid cache URL')
        else:
            if not a.online:raise ValueError('No cached response; --online explicitly enables retrieval')
            if halt:raise ValueError(halt)
            if sent>=a.max_requests:raise ValueError('HTTP request cap reached')
            time.sleep(max(0,1-(time.monotonic()-last)));last=time.monotonic();sent+=1
            try:
                request=urllib.request.Request(url,headers={'User-Agent':'CommonDescentListing-ExternalIndex/0.1'})
                with urllib.request.urlopen(request,timeout=20) as r:
                    body=r.read(3_000_001)
                    if len(body)>3_000_000:raise ValueError('Response exceeds 3 MB trial limit')
                    payload=body.decode('utf-8-sig') if text else json.loads(body)
                    response=dict(request_url=url,retrieved_at_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),last_modified=r.headers.get('Last-Modified'),body_sha256=sha(body),payload=payload)
                write(path,response)
            except urllib.error.HTTPError as e:
                if e.code in (429,503):halt=f'Service requested backoff (HTTP {e.code}); remaining uncached requests stopped.'
                raise
        fetches[url]=response;return response
    for q,sources,url in prepared:
        row=dict(id=q['id'],query=q,sources=[dict(id=e['id'],name=e['name'],anchors=e['anchors']) for e in sources],request_url=url,candidates=[])
        try:
            if a.provider=='geonames':
                country=get(url,text=True);admin=get('https://download.geonames.org/export/dump/admin1CodesASCII.txt',text=True)
                if gazetteer is None:gazetteer=geo_records(country['payload'],admin['payload'])
                candidates=geo_matches(gazetteer,q);responses=[country,admin];attribution='GeoNames, CC-BY; country and first-level administrative-region extracts only'
            else:
                response=get(url);responses=[response]
                candidates=col_candidates(response['payload'],plan['dataset_key']) if a.provider=='col' else macro_candidates(response['payload'],url)
                attribution='Catalogue of Life release '+str(plan['dataset_key']) if a.provider=='col' else 'Macrostrat v2, CC-BY 4.0'
            for c in candidates:c['exact_index_name']=any(canon(c['name'])==canon(e['name']) for e in sources)
            status='partial_match' if a.provider=='col' and candidates and all(c.get('service_match_type')=='higherrank' for c in candidates) else ('candidates' if candidates else 'unresolved')
            row.update(status=status,candidates=candidates[:5],candidate_count=len(candidates),truncated=len(candidates)>5,
                       retrieval=[{k:v[k] for k in ['request_url','retrieved_at_utc','body_sha256','last_modified'] if k in v} for v in responses],attribution=attribution)
        except (ValueError,KeyError,urllib.error.URLError,TimeoutError) as e:row.update(status='error',error=str(e))
        results.append(row);print(q['id'],row['status'],len(row['candidates']),flush=True)
    outcomes={key:sum(r['status']==key for r in results) for key in ['candidates','partial_match','unresolved','error']}
    write(a.output/'results.json',dict(schema_version=1,provider=a.provider,episode_guid=plan['episode_guid'],edition=plan['edition'],index_sha256=plan['index_sha256'],baseline_sha256=plan['baseline_sha256'],dataset_key=plan.get('dataset_key'),source_release=plan.get('source_release'),outcomes=outcomes,requests_sent=sent,paid_api_calls=0,published_index_modified=False,results=results))
    esc=lambda v:html.escape(str(v));sections=[]
    for row in results:
        content='<section><h2>'+esc(row['query']['name'])+'</h2><p>'+esc(row['status'])+' · '+esc(row['query'].get('note',''))+'</p>'
        for entry in row['sources']:
            content+='<details open><summary>Indexed wording: '+esc(entry['name'])+'</summary>'
            for anchor in entry['anchors'][:3]:content+='<blockquote>Passage '+str(anchor['passage_id'])+': '+esc(anchor['passage_text'])+'</blockquote>'
            content+='</details>'
        if row['status']=='partial_match':content+='<p><strong>Only a higher-rank match was returned; this does not resolve the species name.</strong></p>'
        if row.get('error'):content+='<p>'+esc(row['error'])+'</p>'
        if row['status']=='unresolved':content+='<p>No candidate within this source/query coverage. Entry is not rejected.</p>'
        if row.get('truncated'):content+='<p>First five of '+str(row['candidate_count'])+' results shown; refine this ambiguous query.</p>'
        for candidate in row['candidates']:
            content+='<article><h3>'+esc(candidate['name'])+'</h3><p>Exact indexed name: '+esc(candidate['exact_index_name'])+' · Requires review</p>'
            for key in ['rank','status','accepted_name','authorship','service_match','service_match_type','level','country_code','admin_code','match_type','kind','base_age_ma','top_age_ma']:
                if candidate.get(key) is not None:content+='<p>'+esc(key.replace('_',' ').capitalize())+': '+esc(candidate[key])+'</p>'
            if candidate.get('kind')=='geologic interval':content+='<p><strong>Time interval, not a geographic place.</strong> Classification of this indexed entry needs review.</p>'
            content+='<a href="'+esc(candidate['url'])+'">Source record</a><details><summary>Full source metadata</summary><pre>'+esc(json.dumps(candidate,indent=2,ensure_ascii=False))+'</pre></details></article>'
        if row.get('attribution'):content+='<p>Source: '+esc(row['attribution'])+'</p>'
        sections.append(content+'</section>')
    page='<!doctype html><html lang="en"><meta charset="utf-8"><title>External dataset review</title><style>body{font:16px system-ui;max-width:1100px;margin:32px auto;background:#f4faf8;color:#18392e}article{background:white;padding:14px;margin:12px 0;border:1px solid #b8ccc2}pre{white-space:pre-wrap;overflow-wrap:anywhere;font-size:13px}section{margin:30px 0}blockquote{border-left:4px solid #88baa4;padding:10px}summary{cursor:pointer}</style><h1>'+esc(a.provider)+' — evidence review</h1><p>Candidate metadata, not automatic confirmation. Names, homonyms, synonyms, location scope and classifications require review. Index and transcript unchanged.</p><p>'+esc(json.dumps(outcomes))+'</p>'+''.join(sections)+'</html>'
    (a.output/'review.html').write_text(page);print('Report:',a.output/'review.html','HTTP requests:',sent)
if __name__=='__main__':main()
PY_EXTERNAL

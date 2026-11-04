#!/bin/zsh
# Rebuild the unresolved report from saved results; no lookups or index writes.
set -euo pipefail
rollout_project="${0:A:h:h:h}"
exec python3 - "$rollout_project" <<'PY_REPORT'
from pathlib import Path
import collections,html,json,sys
root=Path(sys.argv[1]);out=root/'outputs/external-index-rollout';document=json.loads((out/'results.json').read_text());rows=document['results']
# Invalid query syntax is a hard unresolved candidate, not a failed external service.
for r in rows:
 if r['status']=='lookup_error' and r['errors'] and all('Invalid or wildcard taxon name' in s for s in r['errors']):
  r.update(status='hard_unresolved',reason='Indexed wording is not a sufficiently specific scientific-name query')
counts=dict(collections.Counter(r['status'] for r in rows));review=[r for r in rows if r['status']!='applied']
for name,data in [('results.json',document),('unresolved.json',dict(counts=counts,items=review))]:
 p=out/name;tmp=p.with_suffix('.pending');tmp.write_text(json.dumps(data,indent=2,ensure_ascii=False)+'\n');tmp.replace(p)
titles={}
for p in (root/'flutter_app/assets/episodes').glob('*/episode.json'):
 m=json.loads(p.read_text());titles[m['episode_guid']]=m['metadata']['title']
for guid,item in json.loads((root/'work/episode-preparation/library.json').read_text()).items():
 m=json.loads((root/item['package']/'episode.json').read_text());titles[guid]=m['metadata']['title']
labels={'fossil':'Taxonomy','place':'Places','author':'Authors','paper':'Papers','article':'Articles'};esc=lambda v:html.escape(str(v));cards=[]
for r in sorted(review,key=lambda r:(r['kind'],r['name'].casefold())):
 refs=[]
 for a in r.get('source_anchors',r['anchors']):
  guid=a.get('guid','Unknown episode');ref=(titles.get(guid,guid),a.get('passage_id','not recorded'),a.get('passage_text',a.get('quote','No stored passage text')))
  if ref not in refs:refs.append(ref)
 cards.append('<details><summary>'+esc(r['name'])+' · '+esc(labels.get(r['kind'],r['kind']))+' · '+esc(r['status'])+'</summary><p>'+esc(r['reason'])+'</p><p>'+esc('; '.join(r['errors']))+'</p>'+''.join('<blockquote>'+esc(ep)+' — Passage '+esc(pid)+'<br>'+esc(text)+'</blockquote>' for ep,pid,text in refs)+'<pre>'+esc(json.dumps(r.get('candidates',[]),ensure_ascii=False,indent=2))+'</pre></details>')
(out/'review.html').write_text('<!doctype html><html lang="en"><meta charset="utf-8"><title>External index rollout — unresolved</title><style>body{font:16px system-ui;max-width:1100px;margin:30px auto;background:#f2faf7;color:#183a32}details{padding:14px;margin:10px 0;background:white;border:1px solid #bcd0c8}summary{cursor:pointer}pre{white-space:pre-wrap}blockquote{border-left:3px solid #86b5a5;padding:8px}header{position:sticky;top:0;background:#f2faf7;padding:10px}input{width:95%;padding:12px}</style><header><h1>Existing indexes — unresolved items</h1><p>'+esc(json.dumps(counts))+'</p><p>Clear identities applied automatically. Unresolved entries retained. Lookup errors and stale evidence are shown separately. Missing passage numbers are labelled explicitly.</p><input aria-label="Filter unresolved items" placeholder="Filter by name, category, episode or passage" oninput="for(const e of document.querySelectorAll(\'details\'))e.hidden=!e.textContent.toLowerCase().includes(this.value.toLowerCase())"></header>'+''.join(cards)+'</html>')
print('Unresolved report:',counts,out/'review.html')
PY_REPORT

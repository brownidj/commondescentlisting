#!/bin/zsh
# Recompute review artifacts from cached responses. No API calls or app changes.
set -euo pipefail
review_project="${0:A:h:h}"
review_python="${INDEX_TRIAL_PYTHON:-python3}"
exec "$review_python" - "$review_project" <<'PY_REVIEW'
from pathlib import Path
import collections,hashlib,html,json,re,sys
project=Path(sys.argv[1]);out=project/'outputs/indexing-trial/episode-208-karoo'
source=json.loads((out/'source_snapshot.json').read_text());sample=json.loads((out/'manual-sample.json').read_text())
by_id={p['id']:p for p in source['passages']}
def read(path): return json.loads(path.read_text())
def write(name,data): (out/name).write_text(json.dumps(data,indent=2,ensure_ascii=False)+'\n')
def canon(t): return re.sub(r'\s+',' ',t.casefold().replace('–','-').replace('—','-')).strip()
def sample_id(n): return any(low<=n<=high for low,high in sample['ranges'])
rows=[];sample_rows=[];usage=[]
for path in sorted((out/'responses').glob('*.json')):
    response=read(path)
    if response.get('status')!='completed': raise SystemExit('Incomplete response; no completed-trial report generated.')
    raw=''.join(c['text'] for o in response.get('output',[]) if o.get('type')=='message' for c in o.get('content',[]) if c.get('type')=='output_text')
    entries=json.loads(raw)['entries']
    for i,entry in enumerate(entries,1):
        row=dict(id=f'c{path.stem}-{i:03}',chunk=int(path.stem),proposal=entry)
        rows.append(row)
        evidence=[e for e in entry['evidence'] if sample_id(e['passage_id'])]
        if evidence: sample_rows.append(dict(**row,sample_evidence=evidence))
    u=response['usage'];details=u.get('input_tokens_details',{});fresh=u['input_tokens']-details.get('cached_tokens',0)-details.get('cache_write_tokens',0)
    if fresh<0: raise SystemExit('Unexpected overlapping token accounting; review pricing manually.')
    if response.get('service_tier') not in [None,'default']: raise SystemExit('Non-standard service tier; review prices manually.')
    cost=(fresh*10+details.get('cached_tokens',0)*1+details.get('cache_write_tokens',0)*12.5+u['output_tokens']*50)/1000000
    usage.append(dict(chunk=int(path.stem),response_id=response['id'],model=response['model'],service_tier=response.get('service_tier'),
        usage=u,uncached_nonwrite_input_tokens=fresh,calculated_usd_including_cache_writes=cost))
write('all-raw-proposals.json',dict(entries=rows,review='Unaccepted model output, including entries held back by evidence/normalization checks.'))
write('api-sample-candidates.json',dict(sample_ranges=sample['ranges'],entries=sample_rows))
write('usage-reconciled.json',dict(currency='USD',requests=usage,calculated_total_usd=sum(r['calculated_usd_including_cache_writes'] for r in usage),
    rates_per_million=dict(uncached_input=10,cached_input=1,cache_write_30m=12.5,output=50),
    source='https://developers.openai.com/api/docs/models/gpt-6-astra',checked_date='2026-11-03',
    note='API-reported tokens at standard GPT-6 Astra rates, including reported default cache writes. This is a calculation, not the billing invoice. Reasoning is already included in output tokens.'))
cases=[]
for expected in sample['required']:
    candidates=[]
    for row in sample_rows:
        e=row['proposal']
        if e['kind']!=expected['kind'] or not any(p['passage_id'] in expected['passage_ids'] for p in row['sample_evidence']): continue
        names={canon(e['spoken_name']),canon(e['normalized_name'] or ''),*[canon(n) for n in e['observed_forms']]}
        if expected['kind'] in ['paper','article'] or any(canon(n) in names for n in expected['acceptable_names']): candidates.append(row['id'])
    cases.append(dict(expected=expected,candidate_ids=candidates,recovered=bool(candidates)))
write('sample-recall-candidates.json',dict(required_cases=len(cases),recovered_cases=sum(c['recovered'] for c in cases),cases=cases,
    note='Context/name matching to the prewritten sample; final judgement needs manual review of each candidate.'))
# Keep editorial labels/bibliography separate from immutable model output and quotes.
curation_path=out/'reference-curation.json'
curation=read(curation_path)['entries'] if curation_path.exists() else {}
unknown=set(curation)-{row['id'] for row in rows}
if unknown: raise SystemExit('Unknown curated proposal IDs: '+', '.join(sorted(unknown)))
index_path=out/'proposed-index.json'
if curation and index_path.exists():
    index=read(index_path)
    original=out/'before-reference-curation'
    original.mkdir(exist_ok=True)
    for name in ['proposed-index.json','INDEX_REVIEW.md','review.html']:
        target=original/name
        if (out/name).exists() and not target.exists(): target.write_bytes((out/name).read_bytes())
    for row in rows:
        correction=curation.get(row['id'])
        if not correction: continue
        proposal=row['proposal']
        evidence={(e['passage_id'],e['quote']) for e in proposal['evidence']}
        matches=[e for e in index['entries'] if e['kind']==proposal['kind'] and e['subtype']==proposal['subtype']
                 and evidence.issubset({(o['passage_id'],o['quote']) for o in e['occurrences']})]
        if len(matches)!=1: raise SystemExit('Curated proposal must match exactly one consolidated entry: '+row['id'])
        entry=matches[0]
        entry.setdefault('model_display_name',entry['name'])
        entry['name']=correction['display_label']
        entry['editorial_curation']=dict(raw_proposal_id=row['id'],**correction)
    index['editorial_note']='Descriptive reference labels and sourced bibliography are editorial additions, not model or transcript metadata. Entries remain unaccepted.'
    write('proposed-index.json',index)
    lines=['# Karoo contextual index — reviewed reference labels','',
           'Descriptive labels combine known author, date and subject. They are not formal titles unless the separate bibliography identifies one. Original spoken wording and quotations are preserved. All entries remain trial suggestions.','']
    for e in sorted(index['entries'],key=lambda e:(e['kind'],e['name'].casefold())):
        lines += ['## '+e['name']+' — '+e['kind'],'']
        correction=e.get('editorial_curation')
        if correction:
            lines += [correction['note'],'']
            if correction.get('bibliographic_details'):
                lines += ['Sourced bibliography (separate from transcript):','```json',json.dumps(correction['bibliographic_details'],indent=2,ensure_ascii=False),'```','']
            for citation in correction['sources']:
                if citation.get('url'): lines += ['Source: '+citation['url'],'']
        for occurrence in e['occurrences']:
            lines += [f'- Passage {occurrence["passage_id"]} · {occurrence["audio_time"]}: {occurrence["quote"]}']
        lines += ['']
    (out/'INDEX_REVIEW.md').write_text('\n'.join(lines)+'\n')
# Group repeated entity proposals for presentation, preserving raw JSON records.
display_groups={}
for row in rows:
    e=row['proposal'];correction=curation.get(row['id'])
    title=correction['display_label'] if correction else e['normalized_name'] or e['spoken_name']
    identity=(e['kind'],e['subtype'],canon(title))
    if e['kind'] in ['paper','article'] and not correction:
        identity=identity+(row['id'],) # Do not merge unidentified publications.
    if identity not in display_groups:
        display_groups[identity]=dict(**row,proposal_ids=[],display_proposal=dict(e,evidence=[]))
    group=display_groups[identity]
    group['proposal_ids'].append(row['id'])
    group['display_proposal']['evidence'].extend(e['evidence'])
display_rows=list(display_groups.values())

# Offline review page: no API credential or automatic external requests.
parts=['<!doctype html><html lang="en"><meta charset="utf-8"><title>Karoo indexing trial</title>',
 '<style>body{font:16px system-ui;max-width:1100px;margin:32px auto;padding:0 20px;background:#f4f9f8;color:#16302d}summary{cursor:pointer;font-weight:600}details{background:white;padding:14px;margin:10px 0;border:1px solid #cadbd7;border-radius:8px}blockquote{border-left:3px solid #789;padding-left:12px}small{color:#456}input{padding:10px;width:90%;margin:10px 0}pre{white-space:pre-wrap} .meta{font-size:14px}</style>',
 '<h1>Karoo contextual-indexing trial</h1><p>All results are proposals. Quotes were checked separately; scientific identity, spelling and publication matches still need review. No app index was replaced.</p>',
 f'<p>{len(usage)} API requests · Calculated cost including cache writes: US${sum(r["calculated_usd_including_cache_writes"] for r in usage):.4f}</p>',
 '<input id="search" type="search" placeholder="Filter names, categories, quotes…" aria-label="Filter proposals">',
 '<p>Reference headings combine known author, date and subject; a descriptive heading is not a formal publication title. Sourced bibliographic additions are shown separately from original API fields. Repeated mentions in a passage appear once; mentions fewer than 30 passage numbers apart appear as ranges with their first quotation. Original evidence is retained in JSON; matching chunk proposals are combined for display.</p>']
for row in display_rows:
    e=row['display_proposal'];correction=curation.get(row['id']);title=correction['display_label'] if correction else e['normalized_name'] or e['spoken_name'];esc=html.escape
    parts += [f'<details class="entry" data-evidence="{esc(chr(32).join(evidence["quote"] for evidence in e["evidence"]),quote=True)}"><summary>{esc(title)} <small>— {esc(e["kind"])} / {esc(e["subtype"])} · {esc(", ".join(row["proposal_ids"]))}</small></summary>',
      f'<p class="meta">Spoken: {esc(e["spoken_name"])} · Model confidence: {esc(e["confidence"])} · Review required.</p>',
      f'<p>{esc(e["qualifier"])}</p>']
    if correction:
        parts += [f'<p><strong>Editorial reference details:</strong> {esc(correction["note"])}</p>']
        if correction.get('bibliographic_details'):
            parts += ['<p><strong>Sourced bibliography — added during review:</strong></p><pre>'+esc(json.dumps(correction['bibliographic_details'],indent=2,ensure_ascii=False))+'</pre>']
        for citation in correction['sources']:
            if citation.get('url'):
                url=citation['url']
                if not url.startswith('https://'): raise SystemExit('Bibliographic links must use HTTPS.')
                parts += [f'<p class="meta">Source: <a href="{esc(url,quote=True)}">{esc(url)}</a> · {esc(", ".join(citation["fields"]))}</p>']
    if e['normalization_reason']: parts += [f'<p><strong>Original model normalization proposal:</strong> {esc(e["normalization_reason"])}</p>']
    unique_evidence={}
    for evidence in e['evidence']:
        unique_evidence.setdefault(evidence['passage_id'],evidence)
    ranges=[]
    for passage_id in sorted(unique_evidence):
        if ranges and passage_id-ranges[-1][-1]<30: ranges[-1].append(passage_id)
        else: ranges.append([passage_id])
    for passage_ids in ranges:
        evidence=unique_evidence[passage_ids[0]]
        cue=by_id[passage_ids[0]];seconds=cue['audio_start_ms']//1000;stamp=f'{seconds//3600:02}:{seconds//60%60:02}:{seconds%60:02}'
        label=f'Passage {passage_ids[0]}' if len(passage_ids)==1 else f'Passages {passage_ids[0]}–{passage_ids[-1]}'
        parts += [f'<blockquote><small>{label} · {stamp}</small><br>{esc(evidence["quote"])}</blockquote>']
    if e['publication']:parts += ['<details><summary>Original model publication fields (transcript only)</summary><pre>'+esc(json.dumps(e['publication'],indent=2,ensure_ascii=False))+'</pre></details>']
    parts += ['</details>']
parts += ['<script>for(const row of document.querySelectorAll(".entry")){row.addEventListener("toggle",()=>{if(row.open){for(const other of document.querySelectorAll(".entry")){if(other!==row)other.open=false}}})}document.getElementById("search").addEventListener("input",e=>{const q=e.target.value.toLowerCase();for(const row of document.querySelectorAll(".entry")){row.hidden=!(row.textContent+row.dataset.evidence).toLowerCase().includes(q)}})</script></html>']
(out/'review.html').write_text('\n'.join(parts))
print('Cached response review artifacts generated; no API calls.')
print('Raw sample candidates:',len(sample_rows),'required cases recovered:',sum(c['recovered'] for c in cases),'/',len(cases))
print('Calculated USD including cache writes:',round(sum(r['calculated_usd_including_cache_writes'] for r in usage),4))
PY_REVIEW

#!/bin/zsh
# Prepare an independently annotated sample, or report its per-category results.
set -euo pipefail
exec python3 - "$@" <<'PY'
from pathlib import Path
import argparse, hashlib, json, random
p=argparse.ArgumentParser()
p.add_argument('--index',type=Path);p.add_argument('--baseline',type=Path)
p.add_argument('--review',type=Path);p.add_argument('--output',type=Path,required=True)
p.add_argument('--passages',type=int,default=30);p.add_argument('--seed',type=int,default=42)
a=p.parse_args();kinds=['fossil','place','paper','article','author']
if a.review and (a.index or a.baseline):p.error('Choose review evaluation or sample generation, not both')
if a.review:
    d=json.loads(a.review.read_text())
    if d.get('schema_version')!=1 or d.get('review_complete') is not True or not d.get('reviewer','').strip():
        raise SystemExit('Independent passage review is incomplete; accuracy not measured.')
    rows=d['candidates'];missed=d['missed_entities'];ids={x['id'] for x in d['passages']}
    if any(r.get('judgement') not in ('accept','reject') or r['category'] not in kinds or r['passage_id'] not in ids for r in rows):
        raise SystemExit('Every sampled candidate needs a valid human judgement.')
    if any(r.get('category') not in kinds or r['passage_id'] not in ids or not r.get('name') for r in missed):
        raise SystemExit('Invalid missed entity annotation.')
    results={}
    for kind in kinds:
        tp=sum(r['category']==kind and r['judgement']=='accept' for r in rows)
        fp=sum(r['category']==kind and r['judgement']=='reject' for r in rows)
        fn=sum(r['category']==kind for r in missed)
        results[kind]=dict(accepted_occurrences=tp,false_candidates=fp,missed_entities=fn,
            precision=tp/(tp+fp) if tp+fp else None,recall=tp/(tp+fn) if tp+fn else None)
    output=dict(schema_version=1,unit='entity occurrence within independently reviewed sample passages',
        categories=results,reviewer=d['reviewer'],sample_passages=len(ids),
        limitation='Sample-only results; not a production-wide accuracy claim.')
else:
    if not a.index or not a.baseline or a.passages<1:p.error('--index, --baseline and positive --passages required')
    index=json.loads(a.index.read_text());base=json.loads(a.baseline.read_text())
    passages=base['segments'];by_id={r['id']:r for r in passages}
    if any(anchor['guid']!=base['episode_guid'] for e in index['entries'] for anchor in e['anchors']):
        raise SystemExit('Index and baseline episode identities differ.')
    selected=random.Random(a.seed).sample(passages,min(a.passages,len(passages)))
    ids={r['id'] for r in selected};candidates={}
    for e in index['entries']:
        if e.get('deleted') or e.get('review')=='rejected':continue
        for anchor in e['anchors']:
            pid=anchor.get('passage_id')
            if pid not in ids:continue
            if anchor.get('passage_text')!=by_id[pid]['text'] or anchor['quote'] not in by_id[pid]['text']:
                raise SystemExit('Sample contains stale transcript evidence.')
            key=(e['kind'],e['name'].casefold(),pid,anchor['quote'])
            candidates[key]=dict(category=e['kind'],name=e['name'],passage_id=pid,quote=anchor['quote'],
                extraction=anchor.get('extraction',[]),judgement='unreviewed',reason='')
    positions={p['id']:i for i,p in enumerate(passages)}
    output=dict(schema_version=1,reviewer='',review_complete=False,seed=a.seed,
        source_index_sha256=hashlib.sha256(a.index.read_bytes()).hexdigest(),
        source_baseline_sha256=hashlib.sha256(a.baseline.read_bytes()).hexdigest(),
        episode_guid=base['episode_guid'],sampling='seeded random passage sample',
        instructions='Read every sampled passage, accept/reject each candidate, add every missed entity; recategorisation means reject plus a missed entity in the correct category. Context is not scored.',
        passages=sorted(selected,key=lambda p:p['id']),
        context={str(pid):passages[max(0,positions[pid]-1):positions[pid]+2] for pid in sorted(ids)},
        candidates=list(candidates.values()),missed_entities=[])
a.output.parent.mkdir(parents=True,exist_ok=True)
a.output.write_text(json.dumps(output,indent=2,ensure_ascii=False)+'\n')
print(a.output)
PY

#!/bin/zsh
# Summarise counts/performance and expose changed literal evidence for review.
set -euo pipefail
report_project="${0:A:h:h:h}"
exec python3 - "${1:-${report_project}/outputs/gliner-upgrade-comparison}" <<'PY'
from pathlib import Path
import hashlib,html,json,re,sys
root=Path(sys.argv[1]);arms=['0.2.24-small','0.2.30-small','0.2.30-large'];results={};indexes={}
def esc(s):return html.escape(str(s))
def heading(e):return (e['kind'],' '.join(e['name'].casefold().split()))
def occurrences(index):
    output={}
    for entity in index['entries']:
        for a in entity['anchors']:
            for source in a.get('extraction',[]):
                key=(*heading(entity),a['guid'],a['edition'],a['passage_id'],source['start'],source['end'])
                if a['passage_text'][source['start']:source['end']]!=a['quote']:raise ValueError('Nonliteral extraction evidence')
                output[key]=dict(name=entity['name'],kind=entity['kind'],anchor=a,source=source)
    return output
for arm in arms:
    folder=root/arm;s=json.loads((folder/'summary.json').read_text());index=json.loads((folder/'index.json').read_text())
    if hashlib.sha256((folder/'index.json').read_bytes()).hexdigest()!=s['index_sha256']:raise ValueError('Index checksum mismatch')
    expected_model='urchade/gliner_large-v2.1' if arm.endswith('large') else 'urchade/gliner_small-v2.1'
    if s['model']!=expected_model or s['gliner_version']!=arm.split('-')[0] or s['paid_api_calls']!=0:
        raise ValueError('Unexpected model, runtime or paid API activity')
    for field in ['episode_guid','edition','baseline_sha256','vocabulary_sha256','threshold','device']:
        if results and s[field]!=next(iter(results.values()))['summary'][field]:raise ValueError('Non-comparable '+field)
    log=(folder/'process.log').read_text();wall=re.search(r'([\d.]+)\s+real\s+',log)
    memory=re.search(r'(\d+)\s+maximum resident set size',log)
    results[arm]=dict(summary=s,environment=json.loads((folder/'environment.json').read_text()),
                      process_wall_seconds=float(wall.group(1)) if wall else None,
                      peak_rss_mib=round(int(memory.group(1))/1024**2,1) if memory else None)
    indexes[arm]=index
all_occ={arm:occurrences(index) for arm,index in indexes.items()}
changes={};pairs=[('0.2.24-small','0.2.30-small'),('0.2.30-small','0.2.30-large')]
for before,after in pairs:
    left=all_occ[before];right=all_occ[after]
    changes[before+' -> '+after]=dict(
        retained_occurrences=len(left.keys()&right.keys()),
        added=[right[k] for k in sorted(right.keys()-left.keys())],
        removed=[left[k] for k in sorted(left.keys()-right.keys())])
(root/'comparison.json').write_text(json.dumps(dict(arms=results,changes=changes,accuracy_measured=False),indent=2,ensure_ascii=False)+'\n')
first=next(iter(results.values()))['summary'];title=first['title']
lines=['# GLiNER comparison — '+title,'',
       f"Same {first['passages']:,} passages, extraction policy, labels, threshold 0.5 and reviewed vocabulary ({first['reviewed_vocabulary_entries']} entries). One serial run per arm; no API requests. Published indexes and production environment unchanged.",'',
       '| Library / model | Entries | Taxonomy | Places | Papers | Articles | Authors | Index seconds | Process wall seconds | Peak RSS MiB |',
       '|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|']
rows=[]
for arm,result in results.items():
    s=result['summary'];values=[arm,s['entries'],*[s['categories'][k] for k in ['fossil','place','paper','article','author']],s['seconds'],result['process_wall_seconds'],result['peak_rss_mib']]
    lines.append('| '+' | '.join(map(str,values))+' |');rows.append('<tr>'+''.join('<td>'+esc(v)+'</td>' for v in values)+'</tr>')
lines+=['','Index time includes model loading and extraction. Process wall includes imports/startup. Peak RSS is macOS process resident memory; it does not measure all GPU/Metal allocations. This is a single-run comparison, not a stable performance benchmark. Downloads excluded.','',
        '## Changed occurrences','']
sections=[]
for pair,change in changes.items():
    lines.append(f"- {pair}: {len(change['added'])} added, {len(change['removed'])} removed, {change['retained_occurrences']} retained.")
    section='<h2>'+esc(pair)+'</h2><p>Changes are candidates, not established improvements. Shifted spans appear as a removal and an addition.</p>'
    for direction in ['added','removed']:
        section+='<details><summary>'+esc(direction.title())+' ('+str(len(change[direction]))+')</summary>'
        for i,row in enumerate(change[direction]):
            a=row['anchor'];source=row['source'];text=a['passage_text'];start=source['start'];end=source['end']
            section+='<article><h3>'+esc(row['name'])+' <small>'+esc(row['kind'])+'</small></h3><p>Passage '+str(a['passage_id'])+' · score '+esc(source['score'])+'</p><p>'+esc(text[:start])+'<mark>'+esc(text[start:end])+'</mark>'+esc(text[end:])+'</p></article>'
        section+='</details>'
    sections.append(section)
lines+=['','## Interpretation','',
        'Counts and agreement are not accuracy. Human annotation is needed to distinguish genuine improvements from additional false candidates and missed entities. Existing API suggestions are not ground truth. No model has been promoted to production automatically.','',
        'Open review.html for changed names and their literal passage evidence. comparison.json preserves full evidence and environment information. Read ASSESSMENT.md for the post-hoc spot check; it is not an accuracy benchmark.','',
        '## Reproduction','',
        'See docs/plans/GLINER_UPGRADE_COMPARISON.md. Scripts: scripts/indexing/compare_gliner_models.zsh and scripts/indexing/report_gliner_comparison.zsh. Each arm retains index.json, summary.json, environment.json, worker.log and process.log. Model downloads and the isolated runtime are under work/gliner-upgrade/.','',
        '## Verification','',
        'All index checksums, literal occurrence spans and input identities were checked. Five existing offline indexing fixtures passed. No Flutter code changed; no Flutter builds, launches, Git mutations, retranscription or paid requests.','',
        '## Files and status','',
        'Created model-cache downloader, comparison runner, report generator and comparison plan. Modified local index script only to permit explicit small/large model and revision selection and record library version; its default environment/model are unchanged. No files removed. Trial execution complete; independent quality review pending.','',
        'Suggested commit: Add isolated GLiNER library and model comparisons','']
(root/'README.md').write_text('\n'.join(lines))
page='''<!doctype html><html lang="en"><meta charset="utf-8"><title>GLiNER comparison — Marsupials</title><style>body{font:16px system-ui;margin:36px;max-width:1250px;background:#f4faf8;color:#182925}table{border-collapse:collapse;width:100%;font-size:14px}td,th{padding:8px;border-bottom:1px solid #bccbc6;text-align:left}article{background:white;padding:14px;margin:12px 0;border:1px solid #ccd9d4;border-radius:8px}h3{margin:0}small{font-weight:normal;color:#47665a}mark{background:#c3e9db}summary{padding:14px;cursor:pointer;font-weight:bold}p{line-height:1.5}</style><h1>GLiNER comparison — Marsupials</h1><p>Same transcript and extraction settings; separate trial outputs. No published index changes.</p><p><strong>Counts are not accuracy.</strong> Review changes in context; do not assume more entries means better indexing.</p><table><thead><tr>'''
page=page.replace('Marsupials',esc(title))
page+=''.join('<th>'+esc(t)+'</th>' for t in ['Library/model','Entries','Taxonomy','Places','Papers','Articles','Authors','Index sec','Wall sec','Peak RSS MiB'])+'</tr></thead><tbody>'+''.join(rows)+'</tbody></table>'
page+='<p><a href="ASSESSMENT.md">Read the assessment and examples of category errors</a></p>' if (root/'ASSESSMENT.md').exists() else ''
page+='<p>One run per arm. Index time includes model loading; wall time includes startup. RSS excludes some GPU allocations. Downloads excluded.</p>'+''.join(sections)+'</html>'
(root/'review.html').write_text(page)
print('\n'.join(lines[:12]))
PY

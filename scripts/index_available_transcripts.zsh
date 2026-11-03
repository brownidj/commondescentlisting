#!/bin/zsh
# Explicitly requested paid batch; sequential requests share one spending ceiling.
set -euo pipefail
index_project="${0:A:h:h}"
exec "${INDEX_TRIAL_PYTHON:-python3}" - "$index_project" "$@" <<'PY_BATCH'
from pathlib import Path
import argparse,fcntl,json,subprocess,sys
project=Path(sys.argv[1]);parser=argparse.ArgumentParser()
parser.add_argument('--run',action='store_true')
parser.add_argument('--max-usd',type=float,default=12)
args=parser.parse_args(sys.argv[2:])
if not 0<args.max_usd<=12: parser.error('Budget must be positive and at most the approved US$12.')
out=project/'outputs/indexing-app';out.mkdir(exist_ok=True)
lock=(out/'.batch.lock').open('a')
try: fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
except BlockingIOError: raise SystemExit('A batch is already running.')
library=project/'work/episode-preparation/library.json'
local=json.loads(library.read_text()) if library.exists() else {}
packages={}
for path in (project/'flutter_app/assets/episodes').glob('*/episode.json'):
    m=json.loads(path.read_text());packages[m['episode_guid']]=path.parent
for guid,e in local.items(): packages[guid]=project/e['package']
karoo=json.loads((project/'outputs/indexing-trial/episode-208-karoo/source_snapshot.json').read_text())['episode_guid']
jobs=[]
for guid,package in sorted(packages.items()):
    if guid==karoo: continue # Already paid, preserved trial results are reused.
    m=json.loads((package/'episode.json').read_text())
    jobs.append(dict(guid=guid,package=str(package),output=str(out/m['key']),title=m['metadata']['title']))
def usage(job):
    path=Path(job['output'])/'usage.json'
    return json.loads(path.read_text())['calculated_total_usd'] if path.exists() else 0
def uncertain(job):
    path=Path(job['output'])/'unresolved-usage.json'
    return json.loads(path.read_text())['reserved_usd'] if path.exists() else 0
def record():
    data=dict(approved_additional_ceiling_usd=args.max_usd,calculated_additional_usd=sum(usage(j) for j in jobs),unresolved_cost_reserve_usd=sum(uncertain(j) for j in jobs),maximum_accounted_usd=sum(usage(j)+uncertain(j) for j in jobs),jobs=[dict(**j,calculated_usd=usage(j),unresolved_cost_reserve_usd=uncertain(j)) for j in jobs],note='Reported token calculation, not invoice; Karoo prior trial excluded. Unresolved request reserves are upper bounds, not confirmed charges. No automatic retries after transport failures.')
    (out/'batch-usage.json').write_text(json.dumps(data,indent=2)+'\n')
record()
if not args.run:
    for job in jobs: print(job['title'],job['package'])
    print('Inventory only; use --run to submit missing chunks within the combined ceiling.')
    raise SystemExit(0)
for job in jobs:
    remaining=args.max_usd-sum(usage(j)+uncertain(j) for j in jobs if j!=job)
    output=Path(job['output'])
    if (output/'proposed-index.json').exists():
        u=json.loads((output/'usage.json').read_text())
        p=json.loads((output/'prepared.json').read_text())
        if len(u['requests'])==p['chunks'] and all(r['status']=='completed' for r in u['requests']):
            print(job['title']+': completed cached result retained.',flush=True)
            continue
    config=output/'config.json'
    ceiling=json.loads(config.read_text())['max_usd'] if config.exists() else remaining
    if ceiling>remaining+1e-8: raise SystemExit('Frozen episode ceiling exceeds remaining combined budget; review configuration manually.')
    print(job['title'],flush=True)
    command=[str(project/'scripts/index_transcript_trial.zsh'),'--package',job['package'],'--output',job['output'],'--max-usd',str(ceiling)]
    if args.run: command.append('--run')
    result=subprocess.run(command)
    record()
    if result.returncode: raise SystemExit(result.returncode)
print('Batch complete. Calculated additional USD:',round(sum(usage(j) for j in jobs),4),flush=True)
PY_BATCH

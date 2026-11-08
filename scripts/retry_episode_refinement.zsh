#!/bin/zsh
# Explicit one-attempt ChatGPT retry against the selected index revision.
set -euo pipefail
retry_project="${0:A:h:h}"
exec "${EPISODE_PYTHON:-${retry_project}/work/whisperx-trial/venv/bin/python}" -u - "$retry_project" "$@" <<'PY_RETRY'
from pathlib import Path
import argparse,json,subprocess,sys,uuid,urllib.request
project=Path(sys.argv[1]);sys.path.insert(0,str(project/'scripts/indexing/lib'))
from refinement_retry import stage_retry,activate_retry,atomic,load
parser=argparse.ArgumentParser(description='Explicit retry; one new request capped at US$0.50, old attempts preserved.')
parser.add_argument('--guid',required=True);args=parser.parse_args(sys.argv[2:])
# Do not race a preparation already in progress in the local worker.
connection=project/'work/episode-preparation/connection.json'
if connection.exists():
 cfg=load(connection)
 req=urllib.request.Request('http://127.0.0.1:8765/jobs/current',headers={'Authorization':'Bearer '+cfg['token']})
 try:
  with urllib.request.urlopen(req,timeout=3) as r:job=json.load(r)
 except OSError:job=None
 if job and job.get('state') in ['running','cancelling']:raise SystemExit('Wait for the active preparation before retrying ChatGPT.')
run=uuid.uuid4().hex;ctx=stage_retry(project,args.guid,run);entry=ctx['entry']
out=project/'outputs/episodes'/entry['key']/'runs'/run/'refinement';out.mkdir(parents=True)
atomic(out/'retry-context.json',ctx)
command=['/bin/zsh',str(project/'scripts/refine_episode_index.zsh'),'--package',ctx['package'],'--edition',ctx['edition'],'--index',str(Path(ctx['staged'])/'index.json'),'--output',str(out)]
print('Explicit ChatGPT-only retry. No download, transcription or external enrichment. Up to US$0.50 for one request.',flush=True)
print('Output:',out.relative_to(project),flush=True)
with (out/'worker.log').open('w') as log:code=subprocess.call(command,cwd=project,stdout=log,stderr=log)
if code:
 problem=load(out/'api-error.json') if (out/'api-error.json').exists() else load(out/'failure.json') if (out/'failure.json').exists() else {}
 atomic(out/'retry-result.json',dict(state='failed',active_revision_retained=True,problem=problem,refinement_log=str((out/'worker.log').relative_to(project))))
 print((out/'worker.log').read_text());raise SystemExit(code)
result=load(out/'result.json')
if result['state'] in ['completed','partial']:
 summary=activate_retry(ctx)
 atomic(out/'retry-result.json',dict(state=result['state'],activated=True,episode_guid=args.guid,edition=ctx['edition'],index_directory=str(Path(ctx['staged']).relative_to(project)),refinement=result,index_sha256=summary['index_sha256']))
 export=project/'outputs/library-server/library/library.json'
 if export.exists():subprocess.run(['/bin/zsh',str(project/'scripts/export_library.zsh')],cwd=project,check=True)
else:atomic(out/'retry-result.json',dict(state=result['state'],activated=False,refinement=result))
print(json.dumps(load(out/'retry-result.json'),indent=2),flush=True)
PY_RETRY

#!/bin/zsh
# Local macOS worker for the sandboxed app; all jobs use prepare_episode.zsh.
set -euo pipefail
unset PYTHONOPTIMIZE
worker_scripts="${0:A:h}"
worker_project="${worker_scripts:h}"
worker_python="${EPISODE_PYTHON:-${worker_project}/work/whisperx-trial/venv/bin/python}"
[[ -x "$worker_python" ]] || { print -u2 "Missing WhisperX environment: $worker_python"; exit 2; }
exec "$worker_python" -u - "$worker_project" <<'PY'
from pathlib import Path
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlsplit, parse_qs
from datetime import datetime, timezone
from contextlib import contextmanager
import fcntl, hashlib, hmac, json, os, re, secrets, shutil, signal, stat, subprocess, sys, threading, time, uuid, tempfile
import yaml

project=Path(sys.argv[1]).resolve()
sys.path.insert(0,str(project/'scripts/indexing/lib'))
from index_policy import merge_blacklist
from refinement_retry import stage_retry,activate_retry
sys.path.insert(0,str(project/'scripts/episode_pipeline/lib'))
from baseline_timing import refinement_failure_summary
sys.path.insert(0,str(project/'scripts/lib'))
from transcript_pdf_text import transcript_pdf_text
root=project/'work/episode-preparation';root.mkdir(parents=True,exist_ok=True)
lock=(root/'worker.lock').open('a')
try: fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
except BlockingIOError: raise SystemExit('A preparation worker is already running for this project.')
connection_path=root/'connection.json'
if connection_path.exists(): token=json.loads(connection_path.read_text())['token']
else: token=secrets.token_urlsafe(32)
base='http://127.0.0.1:8765'
models_doc=json.loads((project/'scripts/episode_pipeline/models.json').read_text())
models={m['id']:m for m in models_doc['models']}
timing=models_doc['timing_estimates']
episodes=yaml.safe_load((project/'data/episodes.yaml').read_text())['episodes']
by_guid={e['guid']:e for e in episodes if e.get('episode_number') is not None}
mutex=threading.RLock();current=None;process=None;busy=False

def atomic(path,data):
    path.parent.mkdir(parents=True,exist_ok=True)
    pending=path.with_name(path.name+'.pending')
    pending.write_text(json.dumps(data,indent=2)+'\n');pending.replace(path)

def digest(path):
    value=hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda:f.read(4*1024*1024),b''): value.update(block)
    return value.hexdigest()

def key_for(guid):
    key=guid.rsplit('-',1)[-1]
    return key if re.fullmatch(r'[A-Za-z0-9_-]{8,100}',key) else hashlib.sha256(guid.encode()).hexdigest()[:32]

def read_index():
    path=root/'library.json'
    return json.loads(path.read_text()) if path.exists() else {}

@contextmanager
def library_guard():
    with (root/'library.json.lock').open('a') as handle:
        fcntl.lockf(handle,fcntl.LOCK_EX)
        yield

def package_path(entry):
    path=(project/entry['package']).resolve()
    if not path.is_relative_to((root/'packages').resolve()): raise ValueError('Invalid library path.')
    return path

def existing(guid):
    entry=read_index().get(guid)
    if entry:
        path=package_path(entry)
        if (path/'episode.json').is_file(): return path,entry
    path=project/'flutter_app/assets/episodes'/key_for(guid)
    if (path/'episode.json').is_file(): return path,None
    return None,None

def index_directory(package,entry=None):
    if entry and entry.get('index_directory'):
        path=(project/entry['index_directory']).resolve()
        if not path.is_relative_to((root/'index-revisions').resolve()): raise ValueError('Unsafe index revision path.')
        return path
    return package/'indexing'

def enrich(candidate,edition,outputs,index_dir=None,retry=False,enrichment_output=None):
    global process
    index_dir=index_dir or candidate/'indexing';destination=enrichment_output or outputs/'enrichment'
    update(stage='Enriching index from external sources',stage_key='enrich',fraction=0,
           enrichment_summary=dict(state='running'),candidate_package=str(candidate.relative_to(project)),candidate_edition=edition,
           enrichment_index_directory=str(index_dir.relative_to(project)),enrichment_output=str(destination.relative_to(project)))
    command=['/bin/zsh',str(project/'scripts/enrich_episode_index.zsh'),'--package',str(candidate),'--edition',edition,'--index',str(index_dir/'index.json'),'--output',str(destination)]
    if retry: command.append('--retry')
    if os.environ.get('EPISODE_ENRICHMENT_OFFLINE')=='1': command.append('--offline')
    outputs.mkdir(parents=True,exist_ok=True)
    with (outputs/'enrichment.log').open('w') as log:
        process=subprocess.Popen(command,cwd=project,stdout=log,stderr=log,text=True,start_new_session=True)
        update(process_pid=process.pid)
        while process.poll() is None:
            cancelled()
            progress=destination/'progress.json'
            if progress.exists():
                try:
                    value=json.loads(progress.read_text());update(fraction=min(.99,value['fraction']))
                except (ValueError,KeyError): pass
            time.sleep(.3)
        result_code=process.returncode
    process=None;update(process_pid=None);cancelled()
    if result_code: raise RuntimeError('External enrichment could not validate/save this sidecar. Usable edition retained; retry enrichment only. See '+str((outputs/'enrichment.log').relative_to(project)))
    result=json.loads((destination/'summary.json').read_text());update(enrichment_summary=result)
    return result

def export_library_if_configured(outputs):
    global process
    destination=Path(os.environ['EPISODE_LIBRARY_EXPORT']).resolve() if os.environ.get('EPISODE_LIBRARY_EXPORT') else project/'outputs/library-server/library'
    if not os.environ.get('EPISODE_LIBRARY_EXPORT') and not (destination/'library.json').exists():return
    update(stage='Updating server library',stage_key='export',fraction=None)
    with (outputs/'library-export.log').open('w') as log:
        process=subprocess.Popen(['/bin/zsh',str(project/'scripts/export_library.zsh'),'--destination',str(destination)],cwd=project,stdout=log,stderr=log,start_new_session=True)
        update(process_pid=process.pid)
        process.wait();code=process.returncode
    process=None;update(process_pid=None)
    update(export_warning='Server library export failed; active local edition is available. See library-export.log.' if code else None)

def preparation_report(outputs,candidate,index_dir):
    info=json.loads((index_dir/'summary.json').read_text())
    report=dict(baseline_timing_repairs=json.loads((outputs/'transcription-summary.json').read_text()).get('provisional_timing_repairs',0) if (outputs/'transcription-summary.json').exists() else 0,episode_guid=current['guid'],edition=current.get('candidate_edition'),index_sha256=info['index_sha256'],index_summary=info,refinement=current.get('refinement_summary'),enrichment=current.get('enrichment_summary'),export_warning=current.get('export_warning'),enrichment_only=current.get('enrichment_only',False),refinement_only=current.get('refinement_only',False))
    atomic(outputs/'preparation-summary.json',report)
    path=outputs/'README.md';text=path.read_text() if path.exists() else '# '+current.get('title',by_guid[current['guid']]['title'])+' — preparation\n'
    text=text.split('\n## Final preparation result\n',1)[0]
    path.write_text(text+'\n## Final preparation result\n\n'+json.dumps(report,indent=2)+'\n')

def run_refinement(candidate,edition,outputs,index_dir):
    global process
    update(stage='Resolving unconfirmed items using ChatGPT',stage_key='refine',fraction=None)
    refinement_dir=outputs/'refinement';refinement_dir.mkdir(parents=True,exist_ok=True)
    with (refinement_dir/'worker.log').open('w') as refinement_log:
        process=subprocess.Popen(['/bin/zsh',str(project/'scripts/refine_episode_index.zsh'),'--package',str(candidate),'--edition',edition,'--index',str(index_dir/'index.json'),'--output',str(refinement_dir)],cwd=project,stdout=refinement_log,stderr=refinement_log,text=True,start_new_session=True)
        update(process_pid=process.pid)
        while process.poll() is None:
            cancelled();time.sleep(.3)
        result_code=process.returncode
    process=None;update(process_pid=None);cancelled()
    if result_code:
        warning='ChatGPT fallback did not complete; the externally enriched index has been retained.'
        log_lines=(refinement_dir/'worker.log').read_text().strip().splitlines()
        if log_lines: warning+=' '+log_lines[-1][:500]
        usage_path=refinement_dir/'usage.json';marker_path=refinement_dir/'request-started.json'
        usage=json.loads(usage_path.read_text()) if usage_path.exists() else {}
        try: marker=json.loads(marker_path.read_text()) if marker_path.exists() else {}
        except json.JSONDecodeError: marker=dict(reserved_usd=.50)
        problem_path=refinement_dir/'api-error.json'
        problem=json.loads(problem_path.read_text()) if problem_path.exists() else json.loads((refinement_dir/'failure.json').read_text()) if (refinement_dir/'failure.json').exists() else {}
        refinement_report=dict(problem=problem,state='failed',warning=warning,cost_usd=usage.get('cost_usd'),reserved_usd=marker.get('reserved_usd'),possible_billable_request=problem.get('possible_billable_request',bool(marker)),log=str((refinement_dir/'worker.log').relative_to(project)))
    else:
        refinement_report=json.loads((refinement_dir/'result.json').read_text())
    update(refinement_summary=refinement_report)
    return refinement_report

def run_refinement_retry(job,outputs):
    ctx=stage_retry(project,job['guid'],job['id'])
    candidate=Path(ctx['package']);index_dir=Path(ctx['staged']);edition=ctx['edition']
    initial=json.loads((index_dir/'summary.json').read_text())
    update(candidate_package=str(candidate.relative_to(project)),candidate_edition=edition,
           index_summary=initial,enrichment_summary=initial.get('external_enrichment'))
    atomic(outputs/'retry-context.json',ctx)
    report=run_refinement(candidate,edition,outputs,index_dir)
    if report['state']=='failed':raise RuntimeError(report['warning'])
    if report['state']=='not_needed':
        update(state='completed',stage='No unresolved suggestions require ChatGPT',stage_key='ready',fraction=1)
        preparation_report(outputs,candidate,index_dir);return
    with mutex:
        cancelled();summary=activate_retry(ctx);update(activated=True,index_summary=summary)
    export_library_if_configured(outputs);preparation_report(outputs,candidate,index_dir)
    update(state='completed',stage='Ready',stage_key='ready',fraction=1)

def run_enrichment_retry(job,request,outputs):
    guid=job['guid'];old_entry=read_index().get(guid);candidate,entry=existing(guid);source_hashes={}
    retry_id=request.get('retry_job');prior=None
    if retry_id:
        prior=json.loads((root/'jobs'/f'{retry_id}.json').read_text())
        if prior['guid']!=guid:raise ValueError('Retry job belongs to a different episode.')
    # A cancelled/failed post-transcription job may already have a complete staged package.
    if prior and not prior.get('activated') and prior.get('candidate_package'):
        candidate=(project/prior['candidate_package']).resolve();edition=prior['candidate_edition'];entry=None
        if not candidate.is_relative_to((root/'packages').resolve()):raise ValueError('Unsafe staged retry package.')
        index_dir=(project/prior['enrichment_index_directory']).resolve()
        if not index_dir.is_relative_to(root.resolve()):raise ValueError('Unsafe staged retry index.')
        enrichment_out=(project/prior['enrichment_output']).resolve()
        if not enrichment_out.is_relative_to((project/'outputs').resolve()):raise ValueError('Unsafe enrichment output.')
        enrich(candidate,edition,outputs,index_dir,True,enrichment_out)
        target_entry=dict(key=key_for(guid),edition=edition,package=str(candidate.relative_to(project)),model=job['model'],previous=old_entry['edition'] if old_entry else None)
        if index_dir!=candidate/'indexing':target_entry['index_directory']=str(index_dir.relative_to(project))
    else:
        if candidate is None or entry is None:raise ValueError('For a bundled-only episode use scripts/enrich_episode_index.zsh; app enrichment-only retry requires a worker-prepared edition.')
        edition=entry['edition'];source=index_directory(candidate,entry)
        index_dir=root/'index-revisions'/key_for(guid)/job['id'];index_dir.mkdir(parents=True,exist_ok=False)
        for name in ['index.json','summary.json']:
            original=(source/name).read_bytes();source_hashes[source/name]=hashlib.sha256(original).hexdigest();(index_dir/name).write_bytes(original)
        enrich(candidate,edition,outputs,index_dir,True)
        target_entry=dict(entry,index_directory=str(index_dir.relative_to(project)))
    manifest=json.loads((candidate/'episode.json').read_text());summary=json.loads((index_dir/'summary.json').read_text())
    for artifact in manifest['artifacts']:
        payload=(candidate/artifact['file']).resolve()
        if not payload.is_relative_to(candidate.resolve()) or digest(payload)!=artifact['sha256']:raise ValueError('Retry package artifact verification failed.')
    if manifest['episode_guid']!=guid or summary['episode_guid']!=guid or summary['edition']!=edition or summary['index_sha256']!=digest(index_dir/'index.json'):raise ValueError('Enrichment retry identity/checksum mismatch.')
    with mutex,library_guard():
        cancelled();index=read_index()
        if index.get(guid)!=old_entry or any(digest(path)!=expected for path,expected in source_hashes.items()):raise ValueError('Active edition/index changed while enriching; staged result retained.')
        target_entry['index_sha256']=summary['index_sha256'];index[guid]=target_entry;atomic(root/'library.json',index)
        update(activated=True,index_summary=summary)
    export_library_if_configured(outputs);preparation_report(outputs,candidate,index_dir)
    update(state='completed',stage='Ready',stage_key='ready',fraction=1)

def model_for(path):
    provenance=path/'provenance.json'
    value=json.loads(provenance.read_text()).get('transcription',{}).get('model','') if provenance.exists() else ''
    for mid,m in models.items():
        if value in [mid,m['file']]: return mid
    # Legacy reviewed packages predate transcription metadata. Recover a model
    # only when their recorded original TXT hash proves the raw source pairing.
    manifest=json.loads((path/'episode.json').read_text())
    baseline_path=path/manifest['transcript']['reviewed_file']
    if baseline_path.exists():
        review=json.loads(baseline_path.read_text()).get('review',{})
        name=review.get('source','')
        if name and Path(name).name==name:
            raw=project/'outputs/whisper-test'/name
            txt=raw.with_suffix('.txt')
            if raw.exists() and txt.exists() and review.get('original_txt_sha256')==digest(txt):
                value=Path(json.loads(raw.read_text()).get('params',{}).get('model','')).name
                for mid,m in models.items():
                    if value==m['file']: return mid
    return None

def refinement_available():
    path=project/'work/indexing-trial/openai-api-key'
    return (project/'scripts/refine_episode_index.zsh').is_file() and path.is_file() and path.stat().st_size>0 and not (stat.S_IMODE(path.stat().st_mode)&0o077)

def inspect(guid):
    if guid not in by_guid: raise ValueError('Episode is not in the saved catalogue or has no episode number.')
    path,entry=existing(guid)
    prepared=False;seconds=7200;approx=True;model=None
    if path:
        m=json.loads((path/'episode.json').read_text())
        if m['episode_guid']!=guid: raise ValueError('Episode package GUID collision.')
        prepared=(path/m['audio']['file']).is_file() and (path/m['transcript']['reviewed_file']).is_file()
        seconds=m['audio']['duration_ms']/1000;approx=False;model=model_for(path)
    cached=project/'work/episode-pipeline'/key_for(guid)/'source.mp3'
    if not prepared and cached.is_file():
        try:
            probe=subprocess.check_output(['ffprobe','-v','error','-show_entries','format=duration','-of','json',str(cached)],text=True,timeout=8)
            seconds=float(json.loads(probe)['format']['duration']);approx=False
        except (OSError,ValueError,KeyError,subprocess.SubprocessError): pass
    return dict(prepared=prepared,audio_seconds=seconds,duration_estimated=approx,model=model,source_available=bool(path or cached.exists()),refinement_available=refinement_available(),refinement_message="External sources are checked first. If unresolved items remain, configure the OpenAI key with scripts/configure_indexing_key.zsh for ChatGPT fallback; otherwise those items will be retained with a warning.")

def model_list():
    result=[]
    for m in models.values():
        path=project/'work/whisper/models'/m['file']
        result.append(dict(m,available=path.is_file() and path.stat().st_size==m['bytes'],overhead_seconds_per_audio_hour=timing['encoding_seconds_per_audio_hour']+timing['inspection_seconds_per_audio_hour']+timing['alignment_seconds_per_audio_hour'],fixed_seconds=timing['fixed_seconds'],download_bytes_per_second=timing['download_bytes_per_second']))
    return result

def descriptors():
    result=[]
    for guid,entry in read_index().items():
        path=package_path(entry);m=json.loads((path/'episode.json').read_text())
        result.append(dict(guid=guid,edition=entry['edition'],key=entry['key'],audio_identity=m['audio']['identity'],duration_ms=m['audio']['duration_ms'],passage_count=m['transcript']['passage_count'],has_index=(index_directory(path,entry)/'index.json').is_file()))
    return result

def update(**values):
    with mutex:
        current.update(values)
        atomic(root/'jobs'/f"{current['id']}.json",{k:v for k,v in current.items() if k!='cancel'})

def cancelled():
    if current['cancel']: raise InterruptedError('Preparation cancelled. Previous edition retained.')

def terminate(p):
    if p and p.poll() is None:
        try: os.killpg(p.pid,signal.SIGTERM)
        except ProcessLookupError: pass
        try: p.wait(timeout=5)
        except subprocess.TimeoutExpired:
            try: os.killpg(p.pid,signal.SIGKILL)
            except ProcessLookupError: pass
            p.wait()

stage_names={'capture':'Downloading audio','encode':'Encoding audio','inspect':'Checking audio','transcribe':'Transcribing','baseline':'Building passages','align':'Aligning transcript','publish':'Publishing package','index':'Indexing transcript locally'}

def obtain_model(model):
    global process
    target=project/'work/whisper/models'/model['file'];target.parent.mkdir(parents=True,exist_ok=True)
    update(stage='Checking model',fraction=None)
    if target.exists() and target.stat().st_size==model['bytes'] and digest(target)==model['sha256']: return target
    if target.exists(): raise ValueError('Cached model checksum mismatch. Preserve/remove the corrupt cache file before retrying.')
    part=target.with_suffix('.bin.part')
    url=f"https://huggingface.co/ggerganov/whisper.cpp/resolve/{models_doc['revision']}/{model['file']}"
    log=(root/'jobs'/f"{current['id']}-model.log").open('w')
    update(stage='Downloading model',fraction=0)
    try:
        process=subprocess.Popen(['curl','--fail','--silent','--show-error','--location','--retry','2','--connect-timeout','30','--continue-at','-',url,'--output',str(part)],stdout=log,stderr=log,start_new_session=True)
        update(process_pid=process.pid)
        while process.poll() is None:
            cancelled();update(fraction=min(.99,part.stat().st_size/model['bytes']) if part.exists() else 0);time.sleep(.5)
        if process.returncode: raise RuntimeError('Model download failed. See model log; retry resumes the partial download.')
        cancelled();update(stage='Verifying model',fraction=None)
        if part.stat().st_size!=model['bytes'] or digest(part)!=model['sha256']:
            part.rename(part.with_name(part.name+'.bad-'+current['id']))
            raise ValueError('Downloaded model checksum mismatch; model not activated.')
        part.replace(target)
    finally:
        terminate(process);process=None;log.close();update(process_pid=None)
    return target

def run_job(job,request):
    global process,busy
    guid=job['guid'];key=key_for(guid);run=job['id'];active_before=read_index().get(guid)
    work=project/'work/episode-pipeline'/key/'runs'/run
    outputs=project/'outputs/episodes'/key/'runs'/run
    candidate=root/'packages'/key/run
    try:
        if request.get('refinement_only'):
            outputs.mkdir(parents=True,exist_ok=True);run_refinement_retry(job,outputs);return
        if request.get('enrichment_only'):
            outputs.mkdir(parents=True,exist_ok=True);run_enrichment_retry(job,request,outputs);return
        model=models[request['model']];model_path=obtain_model(model);cancelled()
        work.mkdir(parents=True,exist_ok=True);outputs.mkdir(parents=True,exist_ok=True)
        env=dict(os.environ,EPISODE_RUN_ID=run,EPISODE_PACKAGE=str(candidate),EPISODE_JOURNALS=str(work/'new-edition-journals'),EPISODE_DEFER_ENRICHMENT='1')
        resuming=bool(request.get('resume'))
        if resuming:
            saved=json.loads((outputs/'config.json').read_text())
            if saved.get('reused_audio'):env['EPISODE_REUSE_AUDIO']=saved['reused_audio']
        old,_=existing(guid)
        if not resuming and not request['redownload']:
            if old:
                manifest=json.loads((old/'episode.json').read_text());audio=old/manifest['audio']['file']
                update(stage='Checking retained audio',fraction=None)
                if digest(audio)!=manifest['audio']['sha256']: raise ValueError('Retained audio checksum mismatch; choose redownload.')
                env['EPISODE_REUSE_AUDIO']=str(audio)
            else:
                cached=project/'work/episode-pipeline'/key/'source.mp3'
                if cached.is_file(): shutil.copyfile(cached,work/'source.mp3')
        log_path=outputs/'worker.log'
        with log_path.open('a' if resuming else 'w') as log:
            command=['/bin/zsh',str(project/'scripts/prepare_episode.zsh'),str(by_guid[guid]['episode_number']),'--model',str(model_path),'--no-register']
            if resuming:command.append('--resume')
            process=subprocess.Popen(command,cwd=project,env=env,stdout=subprocess.PIPE,stderr=log,text=True,bufsize=1,start_new_session=True)
            child=process
            update(process_pid=child.pid)
            def consume():
                for line in child.stdout:
                    try: log.write(line);log.flush()
                    except ValueError: break
                    with mutex:
                        if line.startswith('PREP_STAGE '):
                            stage=line.strip().split()[-1];update(stage=stage_names.get(stage,stage),stage_key=stage,fraction=0 if stage in ['encode','transcribe','align'] else None)
                        elif line.startswith('out_time_us=') and current.get('stage_key')=='encode':
                            try: update(fraction=min(.99,int(line.split('=')[1])/1000000/current['audio_seconds']))
                            except ValueError: pass
                child.stdout.close()
            reader=threading.Thread(target=consume,daemon=True);reader.start()
            while process.poll() is None:
                cancelled()
                stage=current.get('stage_key');progress=None
                source_probe=outputs/'probes/source.json'
                if source_probe.exists():
                    try: update(audio_seconds=float(json.loads(source_probe.read_text())['format']['duration']))
                    except (ValueError,KeyError): pass
                if stage in ['transcribe','align','index']:
                    file=outputs/({'transcribe':'transcription.log','align':'alignment.log','index':'local-index.log'}[stage])
                    if file.exists():
                        tail=file.read_text(errors='replace')[-12000:]
                        if stage=='transcribe':
                            found=re.findall(r'progress\s*=\s*(\d+)%',tail)
                            if found: progress=int(found[-1])/100
                            else:
                                spans=re.findall(r'--> (\d+):(\d+):(\d+)\.(\d+)',tail)
                                if spans:
                                    h,m,s,ms=map(int,spans[-1]);progress=(h*3600+m*60+s+ms/1000)/current['audio_seconds']
                        elif stage=='index':
                            counts=re.findall(r'LOCAL_INDEX_PROGRESS (\d+) (\d+)',tail)
                            if counts: progress=int(counts[-1][0])/max(1,int(counts[-1][1]))
                        else:
                            chunks=re.findall(r'Chunk (\d+)/(\d+)',tail)
                            if chunks: progress=int(chunks[-1][0])/int(chunks[-1][1])
                        if progress is not None: update(fraction=min(.99,max(0,progress)))
                time.sleep(.5)
            reader.join(timeout=5)
            cancelled()
            if process.returncode:
                # Keep the dialog concise; raw ffmpeg progress belongs in logs.
                stage=current.get('stage_key') or 'startup'
                paths=[outputs/({'align':'alignment.log','transcribe':'transcription.log','index':'local-index.log'}.get(stage,'worker.log'))]
                if paths[0]!=log_path: paths.append(log_path)
                details='No diagnostic message captured.'
                for path in paths:
                    if not path.exists(): continue
                    lines=path.read_text(errors='replace').splitlines()
                    meaningful=[line.strip() for line in lines if re.search(
                        r'(?:Error|Exception|AssertionError|failed|missing|refusing|changed)',line,re.I)]
                    if meaningful:
                        details=meaningful[-1][:500];break
                raise RuntimeError(f'Preparation failed during {stage} (exit {process.returncode}); previous edition retained. '
                    f'{details} Full log: {log_path.relative_to(project)}')
        process=None;update(process_pid=None);cancelled()
        enrich(candidate,run,outputs)
        if request.get('refine_chatgpt',False):run_refinement(candidate,run,outputs,candidate/'indexing')
        else:update(refinement_summary=dict(state='disabled',cost_usd=0))
        update(stage='Activating validated edition',stage_key='activate',fraction=None)
        manifest=json.loads((candidate/'episode.json').read_text())
        if manifest['episode_guid']!=guid: raise ValueError('Candidate identity mismatch.')
        for artifact in manifest['artifacts']:
            payload=(candidate/artifact['file']).resolve()
            if not payload.is_relative_to(candidate.resolve()) or digest(payload)!=artifact['sha256']: raise ValueError('Candidate artifact verification failed.')
        index_summary=json.loads((candidate/'indexing/summary.json').read_text())
        if index_summary['episode_guid']!=guid or index_summary['edition']!=run or digest(candidate/'indexing/index.json')!=index_summary['index_sha256']:
            raise ValueError('Local index checksum or edition mismatch.')
        with mutex,library_guard():
            cancelled();index=read_index();previous=index.get(guid)
            if previous!=active_before:raise ValueError('Active edition changed during preparation; staged result retained.')
            entry=dict(key=key,edition=run,package=str(candidate.relative_to(project)),model=request['model'],previous=previous['edition'] if previous else None)
            index[guid]=entry;atomic(root/'library.json',index)
            update(activated=True,index_summary=index_summary)
        export_library_if_configured(outputs);preparation_report(outputs,candidate,candidate/'indexing')
        update(state='completed',stage='Ready',stage_key='ready',fraction=1)
    except InterruptedError as error:
        if current.get('stage_key')=='enrich':update(enrichment_summary=dict(state='interrupted',warning='Enrichment interrupted. The previous usable index is retained; resume with enrichment-only retry.'))
        update(state='cancelled',stage='Cancelled',fraction=None,error=str(error))
    except Exception as error:
        if current.get('activated'):update(state='completed',stage='Ready (final reporting warning)',fraction=1,error='Edition activated; final reporting/export did not finish: '+str(error))
        else:
            if current.get('stage_key')=='enrich':update(enrichment_summary=dict(state='failed',warning=str(error)))
            update(state='failed',stage='Failed',fraction=None,error=str(error))
    finally:
        terminate(process);process=None
        if request.get('refine_chatgpt') and current.get('refinement_summary') is None:
            update(refinement_summary=refinement_failure_summary(outputs/'refinement'))
        if outputs.exists() and current.get('state')!='completed':
            atomic(outputs/'preparation-summary.json',{k:v for k,v in current.items() if k!='cancel'})
        # A killed job may leave a lock. Remove only our known dead child's lock.
        lock_dir=work/'.processing-lock'
        owner=lock_dir/'owner.txt'
        if owner.exists():
            match=re.search(r'pid=(\d+)',owner.read_text())
            if match:
                try: os.kill(int(match[1]),0)
                except ProcessLookupError:
                    owner.unlink();lock_dir.rmdir()
        with mutex:
            update(finished_at_utc=datetime.now(timezone.utc).isoformat(),finished_timestamp=time.time(),process_pid=None)
            busy=False


def can_resume(job):
    outputs=project/'outputs/episodes'/key_for(job['guid'])/'runs'/job['id']
    return (job.get('state') in ['failed','cancelled'] and not job.get('activated')
        and job.get('stage_key') in ['capture','encode','inspect','transcribe','baseline','align','publish','index']
        and (outputs/'config.json').is_file()
        and not (outputs/'refinement/request-started.json').exists())

def status(job):
    result={k:v for k,v in job.items() if k!='cancel'}
    result['can_resume']=can_resume(job)
    outputs=project/'outputs/episodes'/key_for(job['guid'])/'runs'/job['id']
    if job.get('refine_chatgpt') and not job.get('activated') and job.get('stage_key') in ['capture','encode','inspect','transcribe','baseline','align','publish','index'] and job.get('state') in ['failed','cancelled']:
        result['refinement_summary']=refinement_failure_summary(outputs/'refinement')
    baseline_summary=outputs/'transcription-summary.json'
    if baseline_summary.exists():
        result['baseline_timing_repairs']=json.loads(baseline_summary.read_text()).get('provisional_timing_repairs',0)
    result['elapsed_seconds']=max(0,(job.get('finished_timestamp') or time.time())-job['started_at'])
    hours=job['audio_seconds']/3600;model=models[job['model']]
    costs={'capture':30,'encode':hours*timing['encoding_seconds_per_audio_hour'],'inspect':hours*timing['inspection_seconds_per_audio_hour'],'transcribe':hours*model['transcription_seconds_per_audio_hour'],'baseline':timing['fixed_seconds']*.2,'align':hours*timing['alignment_seconds_per_audio_hour'],'publish':timing['fixed_seconds']*.8,'index':30}
    costs['enrich']=300
    if job.get('refine_chatgpt'): costs['refine']=180
    if job.get('enrichment_only'):costs={'enrich':300}
    if job.get('refinement_only'):costs={'refine':180}
    stage=job.get('stage_key');fraction=job.get('fraction');remaining=None
    if job['state'] in ['running','cancelling'] and not job.get('activated'):
        if stage in costs:
            sequence=list(costs);position=sequence.index(stage)
            remaining=costs[stage]*(1-(fraction or 0))+sum(costs[x] for x in sequence[position+1:])
        else:
            remaining=sum(costs.values())
            if job['stage']=='Downloading model': remaining+=model['bytes']*(1-(fraction or 0))/timing['download_bytes_per_second']
    result['remaining_seconds']=remaining
    return result

class Handler(BaseHTTPRequestHandler):
    def log_message(self,*args): pass
    def authorised(self):
        if self.headers.get('Origin'): return False
        if self.headers.get('Host') not in ['127.0.0.1:8765','localhost:8765']: return False
        supplied=self.headers.get('Authorization','').removeprefix('Bearer ')
        if urlsplit(self.path).path.startswith('/media/'): supplied=parse_qs(urlsplit(self.path).query).get('token',[''])[0]
        return hmac.compare_digest(supplied.encode(),token.encode())
    def reply(self,code,value):
        data=json.dumps(value).encode();self.send_response(code);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(data)));self.send_header('Cache-Control','no-store');self.end_headers();self.wfile.write(data)
    def do_GET(self):
        if not self.authorised(): self.reply(403,dict(error='Unauthorised local connection.'));return
        path=urlsplit(self.path).path
        try:
            if path=='/health': self.reply(200,dict(ready=True));return
            if path=='/models': self.reply(200,model_list());return
            if path=='/library': self.reply(200,descriptors());return
            if path=='/episode': self.reply(200,inspect(parse_qs(urlsplit(self.path).query).get('guid',[''])[0]));return
            if path=='/jobs/current':
                with mutex:
                    value=current
                    if value is None:
                        saved=[json.loads(p.read_text()) for p in (root/'jobs').glob('*.json')]
                        resumable=[j for j in saved if can_resume(j)]
                        value=max(resumable,key=lambda j:j.get('finished_timestamp',j['started_at']),default=None)
                    self.reply(200,status(value) if value else None)
                return
            if path.startswith('/jobs/'):
                jid=path.split('/')[-1]
                if not re.fullmatch('[a-f0-9]{32}',jid): raise ValueError('Invalid job ID.')
                with mutex:
                    value=current if current and current['id']==jid else json.loads((root/'jobs'/f'{jid}.json').read_text())
                    self.reply(200,status(value))
                return
            if path.startswith('/media/'):
                parts=path.split('/');key,edition=parts[2:4];relative='/'.join(parts[4:])
                if not re.fullmatch('[A-Za-z0-9_-]+',key) or not re.fullmatch('[a-f0-9]{32}',edition): raise ValueError('Invalid edition.')
                allowed=['audio.opus','episode.json','transcript/baseline.json','transcript/alignment.json','indexing/index.json']
                if relative not in allowed: raise ValueError('Unsupported package file.')
                file=root/'packages'/key/edition/relative
                if relative=='indexing/index.json':
                    selected=next((e for e in read_index().values() if e['key']==key and e['edition']==edition),None)
                    if selected:file=index_directory(package_path(selected),selected)/'index.json'
                if relative=='audio.opus': self.audio(file);return
                self.reply(200,json.loads(file.read_text()));return
            self.reply(404,dict(error='Not found.'))
        except (ValueError,KeyError,FileNotFoundError) as e: self.reply(400,dict(error=str(e)))
    def audio(self,file,head=False):
        size=file.stat().st_size;start=0;end=size-1;partial=False
        requested=self.headers.get('Range')
        if requested:
            match=re.fullmatch(r'bytes=(\d*)-(\d*)',requested)
            if not match or not any(match.groups()): self.send_error(416);return
            a,b=match.groups()
            if a: start=int(a);end=min(int(b),end) if b else end
            else: start=max(0,size-int(b))
            if not 0<=start<=end<size: self.send_error(416);return
            partial=True
        self.send_response(206 if partial else 200);self.send_header('Content-Type','audio/ogg');self.send_header('Accept-Ranges','bytes');self.send_header('Content-Length',str(end-start+1))
        if partial: self.send_header('Content-Range',f'bytes {start}-{end}/{size}')
        self.end_headers()
        if head: return
        with file.open('rb') as f:
            f.seek(start);remaining=end-start+1
            while remaining:
                data=f.read(min(65536,remaining))
                if not data: break
                try: self.wfile.write(data)
                except (BrokenPipeError,ConnectionResetError): break
                remaining-=len(data)
    def do_HEAD(self):
        if not self.authorised(): self.send_error(403);return
        parts=urlsplit(self.path).path.split('/')
        if len(parts)!=5 or parts[1]!='media' or parts[4]!='audio.opus' or not re.fullmatch('[A-Za-z0-9_-]+',parts[2]) or not re.fullmatch('[a-f0-9]{32}',parts[3]): self.send_error(404);return
        try: self.audio(root/'packages'/parts[2]/parts[3]/'audio.opus',head=True)
        except FileNotFoundError: self.send_error(404)
    def do_POST(self):
        global current,busy
        if not self.authorised(): self.reply(403,dict(error='Unauthorised local connection.'));return
        try:
            path=urlsplit(self.path).path
            length=int(self.headers.get('Content-Length','0'))
            limit=4*1024*1024 if path in ['/index-blacklist','/transcripts/pdf'] else 16384
            if self.headers.get('Content-Type','').split(';')[0]!='application/json' or not 0<length<=limit: raise ValueError('JSON request required (maximum '+str(limit)+' bytes).')
            body=json.loads(self.rfile.read(length));path=urlsplit(self.path).path
            if not isinstance(body,dict):raise ValueError('JSON request must be an object.')
            if path=='/transcripts/pdf':
                guid=body.get('guid');passages=body.get('passages')
                pdf_meta=next((e for e in episodes if e.get('guid')==guid),None)
                if pdf_meta is None or not isinstance(passages,list) or not passages or len(passages)>20000 or not all(isinstance(t,str) and t.strip() for t in passages):raise ValueError('A known episode and non-empty transcript passages are required.')
                destination=project/'docs/transcripts';destination.mkdir(parents=True,exist_ok=True)
                scratch=project/'work/transcript-pdf';scratch.mkdir(parents=True,exist_ok=True)
                meta=pdf_meta;slug=re.sub('[^a-z0-9]+','-',meta['title'].lower()).strip('-')[:70]
                filename='episode-'+str(meta.get('episode_number') or 'side').zfill(3).replace('.','-')+'-'+slug+'-'+uuid.uuid4().hex[:8]+'.pdf'
                with tempfile.TemporaryDirectory(dir=scratch) as temporary:
                    folder=Path(temporary);source=folder/'transcript.txt';pdf=folder/'transcript.pdf'
                    source.write_text(transcript_pdf_text(passages),encoding='utf-8')
                    try:
                        result=subprocess.run(['/bin/zsh',str(project/'scripts/export_transcript_pdf.zsh'),str(source),str(pdf)],capture_output=True,text=True,timeout=110)
                    except subprocess.TimeoutExpired:raise ValueError('PDF creation timed out; please try again.')
                    if result.returncode or not pdf.is_file():
                        (scratch/'last-error.log').write_text(result.stderr)
                        raise ValueError('PDF creation failed. See work/transcript-pdf/last-error.log on the worker.')
                    pdf.replace(destination/filename)
                self.reply(200,dict(path=str(destination/filename)));return
            if path=='/index-blacklist':
                if not isinstance(body,dict):raise ValueError('Invalid deletion blacklist.')
                with mutex:
                    if busy:self.reply(409,dict(error='Wait for the current preparation before updating the deletion blacklist.'));return
                    count=merge_blacklist(project,body)
                self.reply(200,dict(recorded_deletions=count));return
            if path=='/jobs':
                guid=body.get('guid');mid=body.get('model');replace=body.get('replace');redownload=body.get('redownload');refine=body.get('refine_chatgpt',False)
                if guid not in by_guid or mid not in models or type(replace)!=bool or type(redownload)!=bool or type(refine)!=bool: raise ValueError('Invalid preparation request.')
                enrichment_only=body.get('enrichment_only',False);refinement_only=body.get('refinement_only',False);retry_job=body.get('retry_job')
                if type(enrichment_only)!=bool or type(refinement_only)!=bool or (retry_job is not None and (not isinstance(retry_job,str) or not re.fullmatch('[a-f0-9]{32}',retry_job))):raise ValueError('Invalid enrichment retry request.')
                if enrichment_only and (refine or redownload):raise ValueError('Enrichment-only retry cannot transcribe, redownload or call ChatGPT.')
                if refinement_only and (enrichment_only or not refine or redownload):raise ValueError('ChatGPT-only retry cannot transcribe, redownload or enrich.')
                prior=None
                if retry_job and not enrichment_only and not refinement_only:
                    prior_path=root/'jobs'/f'{retry_job}.json'
                    if not prior_path.exists():raise ValueError('Saved preparation job not found.')
                    prior=json.loads(prior_path.read_text())
                    if prior['guid']!=guid or prior['model']!=mid or redownload or not can_resume(prior):raise ValueError('This preparation cannot safely resume; use a new preparation or a stage-specific retry.')
                    if refine!=prior.get('refine_chatgpt',False):raise ValueError('Resume must preserve the saved ChatGPT choice.')
                    body['resume']=True
                body['resume']=prior is not None
                info=inspect(guid)
                if refinement_only and not info['prepared']:raise ValueError('Prepare an episode before retrying ChatGPT.')
                # Credential is required only if external enrichment leaves fallback candidates.
                if prior is None and not enrichment_only and not refinement_only and info['prepared'] and not replace: raise ValueError('Confirm re-preparation before replacing an edition.')
                if prior is None and not enrichment_only and not refinement_only and info['prepared'] and not redownload:
                    rank=models.get(info['model'],{}).get('rank')
                    if rank is None or models[mid]['rank']<=rank: raise ValueError('Select a larger model, or explicitly redownload.')
                with mutex:
                    if busy: self.reply(409,dict(error='Another episode is being prepared.'));return
                    if prior is not None:
                        attempt_dir=project/'outputs/episodes'/key_for(guid)/'runs'/retry_job/'resume-history'
                        atomic(attempt_dir/(uuid.uuid4().hex+'.json'),prior)
                    busy=True
                    current=dict(id=prior['id'] if prior else uuid.uuid4().hex,guid=guid,title=by_guid[guid]['title'],model=mid,refine_chatgpt=refine,enrichment_only=enrichment_only,refinement_only=refinement_only,state='running',stage='Starting',stage_key=prior.get('stage_key','') if prior else '',fraction=None,error=None,cancel=False,started_at=time.time(),audio_seconds=info['audio_seconds'])
                    update();threading.Thread(target=run_job,args=(current,body),daemon=True).start();self.reply(202,status(current))
                return
            if path.endswith('/cancel'):
                jid=path.split('/')[-2]
                with mutex:
                    if current and current['id']==jid and current['state']=='running':
                        if current.get('activated'):raise ValueError('Edition is already activated; final reporting/export is finishing.')
                        current['cancel']=True;update(state='cancelling',stage='Cancelling')
                    self.reply(200,dict(ok=True))
                return
            self.reply(404,dict(error='Not found.'))
        except (ValueError,KeyError,TypeError,FileNotFoundError) as e: self.reply(400,dict(error=str(e)))

if __name__ == '__main__':
    # A previous worker can be killed while its child is still alive. Never start
    # overlapping jobs or silently steal their processing locks.
    for saved in (root/'jobs').glob('*.json'):
        prior=json.loads(saved.read_text())
        if prior.get('state') not in ['running','cancelling']: continue
        child_pid=prior.get('process_pid')
        if child_pid:
            try: os.kill(child_pid,0)
            except ProcessLookupError: pass
            else: raise SystemExit(f"Previous preparation process {child_pid} is still active. Stop or wait for it before restarting the worker.")
        prior.update(state='completed' if prior.get('activated') else 'failed',stage='Ready (final reporting interrupted)' if prior.get('activated') else 'Interrupted',fraction=1 if prior.get('activated') else None,error='Worker stopped after activation; local edition is available. Check library export.' if prior.get('activated') else 'Worker stopped before completion. Previous active edition retained.',finished_timestamp=time.time())
        atomic(saved,prior)
    
    def interrupted(signum,frame): raise KeyboardInterrupt
    signal.signal(signal.SIGTERM,interrupted)
    server=ThreadingHTTPServer(('127.0.0.1',8765),Handler)
    server.daemon_threads=True
    atomic(connection_path,dict(url=base,token=token));connection_path.chmod(0o600)
    print('Episode preparation worker ready at '+base+'. Keep this Terminal running.')
    print('In the app, select an episode and choose Prepare episode, then select this project folder once.')
    try: server.serve_forever()
    except KeyboardInterrupt: pass
    finally:
        with mutex:
            if current and current['state']=='running': current['cancel']=True
        terminate(process);server.server_close()

PY

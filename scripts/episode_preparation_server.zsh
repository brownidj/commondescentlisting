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
import fcntl, hashlib, hmac, json, os, re, secrets, shutil, signal, stat, subprocess, sys, threading, time, uuid
import yaml

project=Path(sys.argv[1]).resolve()
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
    return dict(prepared=prepared,audio_seconds=seconds,duration_estimated=approx,model=model,source_available=bool(path or cached.exists()),refinement_available=refinement_available(),refinement_message="Configure the OpenAI key with scripts/configure_indexing_key.zsh on the Mac, or turn off ChatGPT refinement.")

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
        result.append(dict(guid=guid,edition=entry['edition'],key=entry['key'],audio_identity=m['audio']['identity'],duration_ms=m['audio']['duration_ms'],passage_count=m['transcript']['passage_count'],has_index=(path/'indexing/index.json').is_file()))
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
    guid=job['guid'];key=key_for(guid);run=job['id']
    work=project/'work/episode-pipeline'/key/'runs'/run
    outputs=project/'outputs/episodes'/key/'runs'/run
    candidate=root/'packages'/key/run
    try:
        model=models[request['model']];model_path=obtain_model(model);cancelled()
        work.mkdir(parents=True,exist_ok=True);outputs.mkdir(parents=True,exist_ok=True)
        env=dict(os.environ,EPISODE_RUN_ID=run,EPISODE_PACKAGE=str(candidate),EPISODE_JOURNALS=str(work/'new-edition-journals'))
        old,_=existing(guid)
        if not request['redownload']:
            if old:
                manifest=json.loads((old/'episode.json').read_text());audio=old/manifest['audio']['file']
                update(stage='Checking retained audio',fraction=None)
                if digest(audio)!=manifest['audio']['sha256']: raise ValueError('Retained audio checksum mismatch; choose redownload.')
                env['EPISODE_REUSE_AUDIO']=str(audio)
            else:
                cached=project/'work/episode-pipeline'/key/'source.mp3'
                if cached.is_file(): shutil.copyfile(cached,work/'source.mp3')
        log_path=outputs/'worker.log'
        with log_path.open('w') as log:
            process=subprocess.Popen(['/bin/zsh',str(project/'scripts/prepare_episode.zsh'),str(by_guid[guid]['episode_number']),'--model',str(model_path),'--no-register'],cwd=project,env=env,stdout=subprocess.PIPE,stderr=log,text=True,bufsize=1,start_new_session=True)
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
        if request.get('refine_chatgpt',False):
            update(stage='Refining index using ChatGPT',stage_key='refine',fraction=None)
            refinement_dir=outputs/'refinement';refinement_dir.mkdir(parents=True,exist_ok=True)
            with (refinement_dir/'worker.log').open('w') as refinement_log:
                process=subprocess.Popen(['/bin/zsh',str(project/'scripts/refine_episode_index.zsh'),'--package',str(candidate),'--edition',run,'--output',str(refinement_dir)],cwd=project,stdout=refinement_log,stderr=refinement_log,text=True,start_new_session=True)
                update(process_pid=process.pid)
                while process.poll() is None:
                    cancelled();time.sleep(.3)
                result_code=process.returncode
            process=None;update(process_pid=None);cancelled()
            if result_code:
                warning='ChatGPT refinement did not complete; the local index has been retained.'
                log_lines=(refinement_dir/'worker.log').read_text().strip().splitlines()
                if log_lines: warning+=' '+log_lines[-1][:500]
                usage_path=refinement_dir/'usage.json';marker_path=refinement_dir/'request-started.json'
                usage=json.loads(usage_path.read_text()) if usage_path.exists() else {}
                try: marker=json.loads(marker_path.read_text()) if marker_path.exists() else {}
                except json.JSONDecodeError: marker=dict(reserved_usd=.50)
                refinement_report=dict(state='failed',warning=warning,cost_usd=usage.get('cost_usd'),reserved_usd=marker.get('reserved_usd'),possible_billable_request=bool(marker),log=str((refinement_dir/'worker.log').relative_to(project)))
            else:
                refinement_report=json.loads((refinement_dir/'result.json').read_text())
            update(refinement_summary=refinement_report)
        else: update(refinement_summary=dict(state='disabled',cost_usd=0))
        update(stage='Activating validated edition',stage_key='activate',fraction=None)
        manifest=json.loads((candidate/'episode.json').read_text())
        if manifest['episode_guid']!=guid: raise ValueError('Candidate identity mismatch.')
        for artifact in manifest['artifacts']:
            payload=(candidate/artifact['file']).resolve()
            if not payload.is_relative_to(candidate.resolve()) or digest(payload)!=artifact['sha256']: raise ValueError('Candidate artifact verification failed.')
        index_summary=json.loads((candidate/'indexing/summary.json').read_text())
        if index_summary['episode_guid']!=guid or index_summary['edition']!=run or digest(candidate/'indexing/index.json')!=index_summary['index_sha256']:
            raise ValueError('Local index checksum or edition mismatch.')
        with mutex:
            cancelled();index=read_index();previous=index.get(guid)
            entry=dict(key=key,edition=run,package=str(candidate.relative_to(project)),model=request['model'],previous=previous['edition'] if previous else None)
            index[guid]=entry;atomic(root/'library.json',index)
            update(state='completed',stage='Ready',fraction=1,activated=True,index_summary=index_summary)
    except InterruptedError as error: update(state='cancelled',stage='Cancelled',fraction=None,error=str(error))
    except Exception as error: update(state='failed',stage='Failed',fraction=None,error=str(error))
    finally:
        terminate(process);process=None
        if request.get('refine_chatgpt') and current.get('refinement_summary') is None:
            review_dir=outputs/'refinement';usage_path=review_dir/'usage.json';marker_path=review_dir/'request-started.json'
            usage=json.loads(usage_path.read_text()) if usage_path.exists() else {}
            try: marker=json.loads(marker_path.read_text()) if marker_path.exists() else {}
            except json.JSONDecodeError: marker=dict(reserved_usd=.50)
            update(refinement_summary=dict(state='failed',warning='Refinement was interrupted or preparation did not reach refinement; inspect saved usage before retrying.',cost_usd=usage.get('cost_usd'),reserved_usd=marker.get('reserved_usd'),possible_billable_request=bool(marker)))
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


def status(job):
    result={k:v for k,v in job.items() if k!='cancel'}
    result['elapsed_seconds']=max(0,(job.get('finished_timestamp') or time.time())-job['started_at'])
    hours=job['audio_seconds']/3600;model=models[job['model']]
    costs={'capture':30,'encode':hours*timing['encoding_seconds_per_audio_hour'],'inspect':hours*timing['inspection_seconds_per_audio_hour'],'transcribe':hours*model['transcription_seconds_per_audio_hour'],'baseline':timing['fixed_seconds']*.2,'align':hours*timing['alignment_seconds_per_audio_hour'],'publish':timing['fixed_seconds']*.8,'index':30}
    if job.get('refine_chatgpt'): costs['refine']=180
    stage=job.get('stage_key');fraction=job.get('fraction');remaining=None
    if job['state'] in ['running','cancelling']:
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
                with mutex: self.reply(200,status(current) if current else None)
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
            length=int(self.headers.get('Content-Length','0'))
            if self.headers.get('Content-Type','').split(';')[0]!='application/json' or not 0<length<=16384: raise ValueError('JSON request required (maximum 16 KiB).')
            body=json.loads(self.rfile.read(length));path=urlsplit(self.path).path
            if path=='/jobs':
                guid=body.get('guid');mid=body.get('model');replace=body.get('replace');redownload=body.get('redownload');refine=body.get('refine_chatgpt',False)
                if guid not in by_guid or mid not in models or type(replace)!=bool or type(redownload)!=bool or type(refine)!=bool: raise ValueError('Invalid preparation request.')
                info=inspect(guid)
                if refine and not info['refinement_available']: raise ValueError(info['refinement_message'])
                if info['prepared'] and not replace: raise ValueError('Confirm re-preparation before replacing an edition.')
                if info['prepared'] and not redownload:
                    rank=models.get(info['model'],{}).get('rank')
                    if rank is None or models[mid]['rank']<=rank: raise ValueError('Select a larger model, or explicitly redownload.')
                with mutex:
                    if busy: self.reply(409,dict(error='Another episode is being prepared.'));return
                    busy=True
                    current=dict(id=uuid.uuid4().hex,guid=guid,title=by_guid[guid]['title'],model=mid,refine_chatgpt=refine,state='running',stage='Starting',stage_key='',fraction=None,error=None,cancel=False,started_at=time.time(),audio_seconds=info['audio_seconds'])
                    update();threading.Thread(target=run_job,args=(current,body),daemon=True).start();self.reply(202,status(current))
                return
            if path.endswith('/cancel'):
                jid=path.split('/')[-2]
                with mutex:
                    if current and current['id']==jid and current['state']=='running': current['cancel']=True;update(state='cancelling',stage='Cancelling')
                    self.reply(200,dict(ok=True))
                return
            self.reply(404,dict(error='Not found.'))
        except (ValueError,KeyError,TypeError) as e: self.reply(400,dict(error=str(e)))

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
        prior.update(state='failed',stage='Interrupted',fraction=None,error='Worker stopped before completion. Previous active edition retained.',finished_timestamp=time.time())
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

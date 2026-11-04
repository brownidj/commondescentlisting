#!/bin/zsh
# Offline worker regressions. No model/media download, pipeline or app launch.
set -euo pipefail
worker_test_scripts="${0:A:h:h}"
worker_test_project="${worker_test_scripts:h}"
worker_test_python="${EPISODE_PYTHON:-${worker_test_project}/work/whisperx-trial/venv/bin/python}"
"$worker_test_python" - "$worker_test_project" <<'PY'
from pathlib import Path
import hashlib,http.client,io,json,os,sys,tempfile,threading,unittest
project=Path(sys.argv[1]);sys.path.insert(0,str(project/'scripts/indexing/lib'));source=(project/'scripts/episode_preparation_server.zsh').read_text().split("<<'PY'\n",1)[1].rsplit('\nPY',1)[0]

class WorkerTest(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='worker-fixture-',dir=project/'work')
        self.project=Path(self.temp.name);(self.project/'scripts/episode_pipeline').mkdir(parents=True);(self.project/'data').mkdir()
        (self.project/'scripts/episode_pipeline/models.json').write_bytes((project/'scripts/episode_pipeline/models.json').read_bytes())
        (self.project/'data/episodes.yaml').write_text('episodes:\n  - guid: fixture-guid\n    episode_number: "1"\n    title: Fixture\n')
        old_argv=sys.argv;sys.argv=['worker',str(self.project)]
        self.ns={'__name__':'worker_fixture'}
        try: exec(compile(source,'worker-inline','exec'),self.ns)
        finally: sys.argv=old_argv
        self.edition='a'*32;self.key='fixture-key';self.media=self.ns['root']/'packages'/self.key/self.edition;self.media.mkdir(parents=True)
        self.audio=bytes(range(256));(self.media/'audio.opus').write_bytes(self.audio)
        self.manifest={'episode_guid':'fixture-guid','audio':{'file':'audio.opus','sha256':hashlib.sha256(self.audio).hexdigest(),'duration_ms':5000,'identity':'sha256:'+hashlib.sha256(self.audio).hexdigest()},'transcript':{'reviewed_file':'transcript/baseline.json','passage_count':1}}
        (self.media/'episode.json').write_text(json.dumps(self.manifest));(self.media/'provenance.json').write_text(json.dumps({'transcription':{'model':'medium.en'}}));(self.media/'transcript').mkdir();(self.media/'transcript/baseline.json').write_text('{}')
        self.index={'fixture-guid':{'key':self.key,'edition':self.edition,'package':str(self.media.relative_to(self.project))}}
        self.ns['atomic'](self.ns['root']/'library.json',self.index)
        self.server=self.ns['ThreadingHTTPServer'](('127.0.0.1',0),self.ns['Handler']);self.thread=threading.Thread(target=self.server.serve_forever,daemon=True);self.thread.start()
    def tearDown(self):
        self.server.shutdown();self.server.server_close();self.thread.join();self.ns['lock'].close();self.temp.cleanup()
    def request(self,method,path,*,auth=True,body=None,extra=None):
        connection=http.client.HTTPConnection('127.0.0.1',self.server.server_port,timeout=3)
        headers={'Host':'127.0.0.1:8765'}
        if auth: headers['Authorization']='Bearer '+self.ns['token']
        if body is not None: headers['Content-Type']='application/json';body=json.dumps(body)
        headers.update(extra or {});connection.request(method,path,body,headers);response=connection.getresponse();result=response.status,response.read(),dict(response.headers);connection.close();return result
    def test_blacklist_requires_auth_and_keeps_earlier_deletions(self):
        body=dict(schema_version=1,entries=[dict(id='old',kind='place',name='The Example',deleted=True,aliases=[],variant_ids=[])])
        self.assertEqual(self.request('POST','/index-blacklist',auth=False,body=body)[0],403)
        self.assertFalse((self.project/'data/index_deletion_blacklist.json').exists())
        self.assertEqual(self.request('POST','/index-blacklist',body=body)[0],200)
        self.assertEqual(self.request('POST','/index-blacklist',body=dict(schema_version=1,entries=[]))[0],200)
        saved=json.loads((self.project/'data/index_deletion_blacklist.json').read_text())
        self.assertEqual(len(saved['entries']),1);self.assertEqual(saved['entries'][0]['name'],'The Example')
        self.assertEqual(self.request('POST','/index-blacklist',body=dict(schema_version=1,entries=[dict(body['entries'][0],kind='invalid')]))[0],400)
    def test_auth_and_browser_origin_rejected(self):
        self.assertEqual(self.request('GET','/health',auth=False)[0],403)
        self.assertEqual(self.request('GET','/health',extra={'Origin':'https://example.com'})[0],403)
        self.assertEqual(self.request('GET','/health')[0],200)
    def test_media_range_head_and_path_constraints(self):
        path=f'/media/{self.key}/{self.edition}/audio.opus?token='+self.ns['token']
        code,body,headers=self.request('GET',path,extra={'Range':'bytes=10-19'})
        self.assertEqual(code,206);self.assertEqual(body,self.audio[10:20]);self.assertEqual(headers['Content-Range'],'bytes 10-19/256')
        code,body,headers=self.request('HEAD',path)
        self.assertEqual(code,200);self.assertEqual(body,b'');self.assertEqual(headers['Content-Length'],'256')
        self.assertNotEqual(self.request('GET',path.replace('audio.opus','../../connection.json'))[0],200)
    def test_confirmation_and_strictly_larger_model_required(self):
        body={'guid':'fixture-guid','model':'medium.en','replace':False,'redownload':False}
        self.assertEqual(self.request('POST','/jobs',body=body)[0],400)
        body['replace']=True
        self.assertEqual(self.request('POST','/jobs',body=body)[0],400)
        body['model']='small.en'
        self.assertEqual(self.request('POST','/jobs',body=body)[0],400)
        self.assertEqual(self.ns['read_index'](),self.index)
    def test_failed_pipeline_never_replaces_active_edition(self):
        class FailedProcess:
            pid=99999999
            returncode=1
            stdout=io.StringIO('PREP_STAGE publish\n'+('out_time_us=6543509396\n'*200)+'AssertionError: Run catalogue snapshot changed or missing.\n')
            def poll(self): return 1
        original=self.ns['subprocess'].Popen
        self.ns['subprocess'].Popen=lambda *a,**kw:FailedProcess()
        self.ns['obtain_model']=lambda m:self.project/'unused-model.bin'
        job={'id':'b'*32,'guid':'fixture-guid','model':'large-v3','state':'running','stage':'Starting','stage_key':'','fraction':None,'error':None,'cancel':False,'started_at':self.ns['time'].time(),'audio_seconds':5}
        self.ns['current']=job;self.ns['busy']=True
        try: self.ns['run_job'](job,{'model':'large-v3','redownload':True})
        finally: self.ns['subprocess'].Popen=original
        self.assertEqual(job['state'],'failed');self.assertFalse(self.ns['busy'])
        self.assertIn('during publish (exit 1)',job['error'])
        self.assertIn('snapshot changed or missing',job['error'])
        self.assertIn('Full log: outputs/',job['error'])
        self.assertNotIn('out_time_us=',job['error'])
        self.assertLess(len(job['error']),1000)
        self.assertEqual(self.ns['read_index'](),self.index);self.assertEqual((self.media/'audio.opus').read_bytes(),self.audio)

    def test_refinement_credential_is_deferred_until_fallback(self):
        code,body,_=self.request('GET','/episode?guid=fixture-guid')
        self.assertEqual(code,200);self.assertFalse(json.loads(body)['refinement_available'])
        def no_preparation(job,request):
            self.ns['update'](state='completed');self.ns['busy']=False
        self.ns['run_job']=no_preparation
        request=dict(guid='fixture-guid',model='large-v3',replace=True,redownload=True,refine_chatgpt=True)
        self.assertEqual(self.request('POST','/jobs',body=request)[0],202)
        request['refine_chatgpt']='yes'
        self.assertEqual(self.request('POST','/jobs',body=request)[0],400)
        self.assertEqual(self.ns['read_index'](),self.index)
    def refinement_fixture(self,cancel=False):
        job={'id':'c'*32,'guid':'fixture-guid','model':'large-v3','state':'running','stage':'Starting','stage_key':'','fraction':None,'error':None,'cancel':False,'started_at':self.ns['time'].time(),'audio_seconds':5,'refine_chatgpt':True}
        self.ns['current']=job;self.ns['busy']=True;self.ns['obtain_model']=lambda m:self.project/'unused-model.bin'
        test=self
        def fake_enrich(candidate,edition,outputs,index_dir=None,retry=False,enrichment_output=None):
            value=dict(state='partial',enriched=0,unresolved=0,stale=0,duplicates_merged=0,warnings=['fixture source outage'])
            self.ns['update'](enrichment_summary=value,candidate_edition=edition)
            return value
        self.ns['enrich']=fake_enrich
        class Process:
            pid=99999999
            def __init__(self,code,refinement=False):self.returncode=code;self.stdout=io.StringIO('PREP_STAGE index\n');self.refinement=refinement
            def poll(self):
                if self.refinement and cancel and self.returncode is None:job['cancel']=True
                return self.returncode
            def wait(self,timeout=None):self.returncode=0;return 0
        def start(command,**kwargs):
            if 'refine_episode_index.zsh' in command[1]:
                if job.get('enrichment_summary') is None:raise AssertionError('External enrichment must run before ChatGPT')
                out=Path(command[command.index('--output')+1]);out.mkdir(parents=True,exist_ok=True)
                if cancel:
                    (out/'request-started.json').write_text(json.dumps(dict(reserved_usd=.25)))
                    return Process(None,True)
                kwargs['stdout'].write('Offline fixture: refinement failure.\n');kwargs['stdout'].flush();return Process(2,True)
            candidate=Path(kwargs['env']['EPISODE_PACKAGE']);candidate.mkdir(parents=True,exist_ok=True)
            (candidate/'audio.opus').write_bytes(test.audio);(candidate/'transcript').mkdir();(candidate/'transcript/baseline.json').write_text('{}')
            manifest=dict(test.manifest,artifacts=[dict(file='audio.opus',sha256=test.ns['digest'](candidate/'audio.opus'))])
            (candidate/'episode.json').write_text(json.dumps(manifest));(candidate/'indexing').mkdir();(candidate/'indexing/index.json').write_text('{"schema_version":1,"entries":[]}')
            (candidate/'indexing/summary.json').write_text(json.dumps(dict(episode_guid='fixture-guid',edition=job['id'],index_sha256=test.ns['digest'](candidate/'indexing/index.json'))))
            return Process(0)
        original=self.ns['subprocess'].Popen;self.ns['subprocess'].Popen=start
        try:self.ns['run_job'](job,dict(model='large-v3',redownload=True,refine_chatgpt=True))
        finally:self.ns['subprocess'].Popen=original
        return job
    def test_refinement_failure_activates_local_index_with_warning(self):
        job=self.refinement_fixture()
        self.assertEqual(job['state'],'completed');self.assertEqual(job['refinement_summary']['state'],'failed');self.assertIn('enriched index',job['refinement_summary']['warning'])
        self.assertFalse(job['refinement_summary']['possible_billable_request']);self.assertEqual(self.ns['read_index']()['fixture-guid']['edition'],job['id'])
    def test_cancelled_refinement_preserves_previous_edition_and_reservation(self):
        job=self.refinement_fixture(cancel=True)
        self.assertEqual(job['state'],'cancelled');self.assertEqual(self.ns['read_index'](),self.index)
        self.assertEqual(job['refinement_summary']['reserved_usd'],.25);self.assertTrue(job['refinement_summary']['possible_billable_request']);self.assertFalse(self.ns['busy'])
    def test_enrichment_only_branch_never_obtains_a_model(self):
        job=dict(id='f'*32,guid='fixture-guid',model='medium.en',state='running',stage='Starting',stage_key='',cancel=False,started_at=self.ns['time'].time(),audio_seconds=5)
        self.ns['current']=job;self.ns['busy']=True;called=[]
        def forbidden(model):raise AssertionError('Recognition/model stage must be bypassed')
        def retry(selected,request,outputs):called.append(selected['id']);self.ns['update'](state='completed')
        self.ns['obtain_model']=forbidden;self.ns['run_enrichment_retry']=retry
        self.ns['run_job'](job,dict(model='medium.en',redownload=False,enrichment_only=True))
        self.assertEqual(called,['f'*32]);self.assertEqual(job['state'],'completed');self.assertEqual(self.ns['read_index'](),self.index)
    def test_cancelled_retry_does_not_replace_active_index_pointer(self):
        source=self.media/'indexing';source.mkdir();(source/'index.json').write_text('{"entries":[]}');(source/'summary.json').write_text('{}')
        original=(source/'index.json').read_bytes();job=dict(id='1'*32,guid='fixture-guid',model='medium.en',cancel=False)
        self.ns['current']=job
        def cancel(*args,**kwargs):raise InterruptedError('fixture cancellation')
        self.ns['enrich']=cancel
        with self.assertRaises(InterruptedError):self.ns['run_enrichment_retry'](job,{},self.project/'outputs/retry')
        self.assertEqual(self.ns['read_index'](),self.index);self.assertEqual((source/'index.json').read_bytes(),original)
    def test_revision_index_is_served_without_changing_audio_edition(self):
        revision=self.ns['root']/'index-revisions'/self.key/('d'*32);revision.mkdir(parents=True)
        (revision/'index.json').write_text('{"schema_version":1,"entries":[],"revision":"new"}')
        self.index['fixture-guid']['index_directory']=str(revision.relative_to(self.project));self.ns['atomic'](self.ns['root']/'library.json',self.index)
        code,body,_=self.request('GET',f'/media/{self.key}/{self.edition}/indexing/index.json')
        self.assertEqual(code,200);self.assertEqual(json.loads(body)['revision'],'new');self.assertEqual((self.media/'audio.opus').read_bytes(),self.audio)
    def test_retry_operation_rejects_paid_or_redownload_flags(self):
        body=dict(guid='fixture-guid',model='medium.en',replace=False,redownload=True,enrichment_only=True)
        self.assertEqual(self.request('POST','/jobs',body=body)[0],400)
        body.update(redownload=False,refine_chatgpt=True)
        self.assertEqual(self.request('POST','/jobs',body=body)[0],400)
    def test_cancel_after_activation_does_not_claim_to_undo_activation(self):
        self.ns['current']=dict(id='e'*32,state='running',activated=True,cancel=False)
        self.assertEqual(self.request('POST','/jobs/'+('e'*32)+'/cancel',body={})[0],400)
        self.assertFalse(self.ns['current']['cancel'])
unittest.main(argv=['worker-fixtures'],verbosity=2)
PY

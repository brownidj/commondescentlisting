#!/bin/zsh
# Offline worker regressions. No model/media download, pipeline or app launch.
set -euo pipefail
worker_test_scripts="${0:A:h:h}"
worker_test_project="${worker_test_scripts:h}"
worker_test_python="${EPISODE_PYTHON:-${worker_test_project}/work/whisperx-trial/venv/bin/python}"
"$worker_test_python" - "$worker_test_project" <<'PY'
from pathlib import Path
import hashlib,http.client,io,json,os,sys,tempfile,threading,unittest
project=Path(sys.argv[1]);source=(project/'scripts/episode_preparation_server.zsh').read_text().split("<<'PY'\n",1)[1].rsplit('\nPY',1)[0]

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

unittest.main(argv=['worker-fixtures'],verbosity=2)
PY

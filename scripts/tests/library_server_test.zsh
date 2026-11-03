#!/bin/zsh
# Temporary offline fixtures only; no real library, media jobs or app launches.
set -euo pipefail
server_test_project="${0:A:h:h:h}"
exec python3 - "$server_test_project" <<'PY_TEST'
from pathlib import Path
import contextlib,hashlib,http.client,json,sys,tempfile,threading,unittest
project=Path(sys.argv[1])
class LibraryServerTest(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name);self.token='a'*40;token_file=self.root/'token';token_file.write_text(self.token)
  self.relative='episodes/'+('a'*24)+'/'+('b'*24)+'/audio.opus';p=self.root/self.relative;p.parent.mkdir(parents=True);p.write_bytes(bytes(range(256)))
  (self.root/'library.json').write_text(json.dumps(dict(schema_version=1,episodes=[],files={self.relative:dict(bytes=256,sha256=hashlib.sha256(bytes(range(256))).hexdigest())})))
  script=(project/'scripts/library_server.zsh').read_text().split("<<'PY_SERVER'\n",1)[1].rsplit('\nPY_SERVER',1)[0]
  ns={'__name__':'fixture'}
  with contextlib.ExitStack() as stack:
   original=sys.argv;sys.argv=['fixture','--library',str(self.root),'--token-file',str(token_file)]
   try:exec(compile(script,'library_server.zsh','exec'),ns)
   finally:sys.argv=original
  self.server=ns['ThreadingHTTPServer'](('127.0.0.1',0),ns['Handler']);self.thread=threading.Thread(target=self.server.serve_forever,daemon=True);self.thread.start()
 def tearDown(self):self.server.shutdown();self.server.server_close();self.thread.join();self.tmp.cleanup()
 def request(self,path,headers=None,method='GET',auth=True):
  c=http.client.HTTPConnection('127.0.0.1',self.server.server_port);h={'Authorization':'Bearer '+self.token} if auth else {};h.update(headers or {});c.request(method,path,headers=h);r=c.getresponse();result=(r.status,r.read(),dict(r.headers));c.close();return result
 def test_auth_readonly_and_paths(self):
  self.assertEqual(self.request('/library',auth=False)[0],403)
  self.assertEqual(self.request('/library',headers={'Origin':'https://example.com'})[0],403)
  self.assertEqual(self.request('/library')[0],200)
  self.assertEqual(self.request('/library',method='POST')[0],405)
  self.assertEqual(self.request('/files/../token')[0],404)
 def test_ranges_and_head(self):
  path='/files/'+self.relative
  status,data,headers=self.request(path,headers={'Range':'bytes=10-19'})
  self.assertEqual((status,data),(206,bytes(range(10,20))))
  self.assertEqual(headers['Content-Range'],'bytes 10-19/256')
  self.assertEqual(self.request(path,headers={'Range':'bytes=300-'})[0],416)
  self.assertEqual(self.request(path,headers={'Range':'bytes=0-1,4-5'})[0],416)
  status,data,headers=self.request(path,method='HEAD');self.assertEqual(data,b'');self.assertEqual(headers['Content-Length'],'256')
unittest.main(argv=['fixtures'],verbosity=2)
PY_TEST

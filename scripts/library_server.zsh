#!/bin/zsh
# Read-only private-LAN prototype, no preparation/administration endpoints.
set -euo pipefail
library_python="${LIBRARY_PYTHON:-python3}"
exec "$library_python" -u - "$@" <<'PY_SERVER'
from pathlib import Path
from http.server import ThreadingHTTPServer,BaseHTTPRequestHandler
from urllib.parse import urlsplit,parse_qs,unquote
import argparse,hashlib,hmac,json,re
parser=argparse.ArgumentParser()
parser.add_argument('--library',required=True,type=Path)
parser.add_argument('--token-file',required=True,type=Path)
parser.add_argument('--host',default='127.0.0.1')
parser.add_argument('--port',default=8766,type=int)
args=parser.parse_args();root=args.library.resolve();token=args.token_file.read_text().strip()
if not re.fullmatch(r'[A-Za-z0-9_-]{32,}',token):raise SystemExit('Read token must contain at least 32 URL-safe characters.')
def snapshot():
 d=json.loads((root/'library.json').read_text())
 if d['schema_version']!=1:raise ValueError('Unsupported library')
 return d
initial=snapshot()
for relative,record in initial['files'].items():
 path=(root/relative).resolve()
 if not path.is_relative_to(root) or not path.is_file() or path.stat().st_size!=record['bytes']:
  raise SystemExit('Library file missing or unsafe; export/copy the complete library again.')
 digest=hashlib.sha256()
 with path.open('rb') as stream:
  for block in iter(lambda:stream.read(1024*1024),b''):digest.update(block)
 if digest.hexdigest()!=record['sha256']:raise SystemExit('Library checksum mismatch; export/copy the complete library again.')
class Handler(BaseHTTPRequestHandler):
 def log_message(self,*args):pass # Never log authenticated query strings.
 def do_POST(self):self.send_error(405)
 def do_PUT(self):self.send_error(405)
 def do_DELETE(self):self.send_error(405)
 def do_HEAD(self):self.serve(True)
 def do_GET(self):self.serve(False)
 def serve(self,head):
  try:
   parsed=urlsplit(self.path)
   supplied=self.headers.get('Authorization','').removeprefix('Bearer ') or parse_qs(parsed.query).get('token',[''])[0]
   if self.headers.get('Origin') or not hmac.compare_digest(supplied.encode(),token.encode()):self.send_error(403);return
   d=snapshot();path=unquote(parsed.path)
   if path=='/library':
    data=json.dumps(d).encode();self.send_response(200);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(data)));self.send_header('Cache-Control','no-store');self.end_headers()
    if not head:self.wfile.write(data)
    return
   if not path.startswith('/files/'):self.send_error(404);return
   relative=path[len('/files/'):];p=(root/relative).resolve()
   # Immutable historical files remain seekable after a newer snapshot publishes.
   if not p.is_relative_to(root) or not re.fullmatch(r'(episodes/[a-f0-9]{24}/[a-f0-9]{24}/(audio\.opus|transcript/(baseline|alignment)\.json|index-[a-f0-9]{24}\.json)|catalogues/[a-f0-9]{64}\.yaml)',relative) or not p.is_file():self.send_error(404);return
   size=p.stat().st_size;start=0;end=size-1;requested=self.headers.get('Range')
   if requested:
    m=re.fullmatch(r'bytes=(\d*)-(\d*)',requested)
    if not m or not any(m.groups()):self.send_error(416);return
    a,z=m.groups()
    if a:start=int(a);end=min(int(z),end) if z else end
    else:start=max(0,size-int(z))
    if start>end or start>=size:self.send_response(416);self.send_header('Content-Range',f'bytes */{size}');self.send_header('Content-Length','0');self.end_headers();return
   self.send_response(206 if requested else 200);self.send_header('Content-Type','audio/ogg' if p.suffix=='.opus' else 'application/json' if p.suffix=='.json' else 'application/yaml');self.send_header('Accept-Ranges','bytes');self.send_header('Content-Length',str(end-start+1));self.send_header('Cache-Control','private, max-age=3600')
   if requested:self.send_header('Content-Range',f'bytes {start}-{end}/{size}')
   self.end_headers()
   if not head:
    with p.open('rb') as stream:
     stream.seek(start);remaining=end-start+1
     while remaining:
      data=stream.read(min(128*1024,remaining))
      if not data:break
      self.wfile.write(data);remaining-=len(data)
  except (BrokenPipeError,ConnectionResetError):pass
  except (OSError,ValueError,KeyError):self.send_error(503,'Library unavailable')
if __name__=='__main__':
 server=ThreadingHTTPServer((args.host,args.port),Handler)
 print(f'Read-only library server listening on {args.host}:{args.port}',flush=True)
 try:server.serve_forever()
 except KeyboardInterrupt:pass
 finally:server.server_close()
PY_SERVER

#!/bin/zsh
# Publish completed editions to a relocatable, read-only library snapshot.
set -euo pipefail
library_project="${0:A:h:h}"
library_python="${EPISODE_PYTHON:-${library_project}/work/whisperx-trial/venv/bin/python}"
exec "$library_python" - "$library_project" "$@" <<'PY_EXPORT'
from pathlib import Path
import argparse,fcntl,hashlib,json,re,shutil,sys
project=Path(sys.argv[1]);parser=argparse.ArgumentParser()
parser.add_argument('--destination',type=Path,default=project/'outputs/library-server/library')
args=parser.parse_args(sys.argv[2:]);root=args.destination.resolve();root.mkdir(parents=True,exist_ok=True)
lock=(root/'.export.lock').open('a');fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
def load(p):return json.loads(p.read_text())
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,d):
 p.parent.mkdir(parents=True,exist_ok=True);tmp=p.with_suffix('.pending');tmp.write_text(json.dumps(d,indent=2,ensure_ascii=False)+'\n');tmp.replace(p)
packages={};index_overrides={}
for p in (project/'flutter_app/assets/episodes').glob('*/episode.json'):
 m=load(p);packages[m['episode_guid']]=(p.parent,m['audio']['identity'])
local=project/'work/episode-preparation/library.json'
if local.exists():
 for guid,e in load(local).items():
  packages[guid]=(project/e['package'],e['edition'])
  if e.get('index_directory'):
   override=(project/e['index_directory']).resolve()
   if not override.is_relative_to((project/'work/episode-preparation/index-revisions').resolve()):raise SystemExit('Unsafe index revision path')
   index_overrides[guid]=override/'index.json'
indexes=load(project/'flutter_app/assets/data/contextual_indexes.json')['entries']
local_indexes=project/'flutter_app/assets/data/local_indexes.json'
if local_indexes.exists():indexes+=load(local_indexes)['entries']
rows=[];files={}
for guid,(package,edition) in sorted(packages.items()):
 package=package.resolve();m=load(package/'episode.json')
 if m['episode_guid']!=guid:raise SystemExit('Episode identity mismatch')
 def artifact(relative):
  p=(package/relative).resolve()
  if not p.is_relative_to(package):raise SystemExit('Unsafe package path')
  record=next((a for a in m['artifacts'] if a['file']==relative),None)
  if not record or p.stat().st_size!=record['byte_length'] or sha(p)!=record['sha256']:raise SystemExit('Package checksum mismatch: '+str(p))
  return p
 key=hashlib.sha256(guid.encode()).hexdigest()[:24];version=hashlib.sha256(edition.encode()).hexdigest()[:24];prefix=f'episodes/{key}/{version}'
 payload={}
 for name,rel in [('audio.opus',m['audio']['file']),('transcript/baseline.json',m['transcript']['reviewed_file']),('transcript/alignment.json',m['transcript']['alignment_file'])]:
  source=artifact(rel);dest=root/prefix/name;dest.parent.mkdir(parents=True,exist_ok=True)
  if dest.exists():
   if sha(dest)!=sha(source):raise SystemExit('Immutable library file collision: '+str(dest))
  else:
   temp=dest.with_suffix('.pending');shutil.copyfile(source,temp);temp.replace(dest)
  relative=str(dest.relative_to(root));files[relative]=dict(sha256=sha(dest),bytes=dest.stat().st_size);payload[name]=relative
 baseline=load(root/payload['transcript/baseline.json']);align=load(root/payload['transcript/alignment.json'])
 if baseline['episode_guid']!=guid or align['audio_identity']!=m['audio']['identity'] or align['source_transcript_sha256']!=sha(root/payload['transcript/baseline.json']):raise SystemExit('Transcript pairing mismatch')
 candidates=list(indexes)
 sidecar=index_overrides.get(guid,package/'indexing/index.json')
 if sidecar.exists():
  summary=load(sidecar.with_name('summary.json'))
  if summary['episode_guid']!=guid or summary['edition']!=edition or summary['index_sha256']!=sha(sidecar):raise SystemExit('Local index mismatch')
  authoritative=load(sidecar)['entries'];ids={e['id'] for e in authoritative}
  candidates=[e for e in candidates if e['id'] not in ids]+authoritative
 selected={};cues={c['id']:c['text'] for c in baseline['segments']}
 for entry in candidates:
  anchors=[a for a in entry['anchors'] if a['guid']==guid and a.get('edition')==edition and a.get('passage_text')==cues.get(a.get('passage_id')) and a['quote'] in a['passage_text']]
  if anchors:selected[entry['id']]=dict(entry,anchors=anchors)
 # Retain only author links that are exported in this edition.
 for e in selected.values():e['author_ids']=[a for a in e['author_ids'] if a in selected]
 index=dict(schema_version=1,entries=list(selected.values()))
 index_bytes=(json.dumps(index,indent=2,ensure_ascii=False)+'\n').encode();index_key=hashlib.sha256(index_bytes).hexdigest()[:24]
 # Index revisions are immutable too; library.json selects the current revision.
 index_path=root/prefix/f'index-{index_key}.json'
 if not index_path.exists():index_path.write_bytes(index_bytes)
 relative=str(index_path.relative_to(root));files[relative]=dict(sha256=sha(index_path),bytes=index_path.stat().st_size);payload['indexing/index.json']=relative
 rows.append(dict(guid=guid,edition=edition,title=m['metadata']['title'],number=m['metadata'].get('number'),audio_identity=m['audio']['identity'],duration_ms=m['audio']['duration_ms'],passage_count=m['transcript']['passage_count'],index_entries=len(selected),files=payload))
catalogue_source=project/'data/segments.yaml';catalogue_name='catalogues/'+sha(catalogue_source)+'.yaml';target=root/catalogue_name;target.parent.mkdir(exist_ok=True)
if not target.exists():shutil.copyfile(catalogue_source,target)
files[catalogue_name]=dict(sha256=sha(target),bytes=target.stat().st_size)
write(root/'library.json',dict(schema_version=1,episodes=rows,catalogue=catalogue_name,files=files))
print(f'Published {len(rows)} completed episode editions to {root}')
print('Copy this library directory and scripts/library_server.zsh to the destination machine; configure a separate read token.')
PY_EXPORT

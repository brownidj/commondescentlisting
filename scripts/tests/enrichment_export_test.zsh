#!/bin/zsh
# Offline export revision selection; all files live in a temporary fixture.
set -euo pipefail
export_test_project="${0:A:h:h:h}"
exec python3 - "$export_test_project" <<'PY_TEST'
from pathlib import Path
import hashlib,json,sys,tempfile,unittest
project=Path(sys.argv[1]);source=(project/'scripts/export_library.zsh').read_text().split("<<'PY_EXPORT'\n",1)[1].rsplit('\nPY_EXPORT',1)[0]
def write(p,d):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(d))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
class EnrichmentExportTest(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory(dir=project/'work',prefix='export-enrichment-');self.root=Path(self.tmp.name);self.destination=self.root/'export';self.guid='fixture';self.edition='a'*32
  self.package=self.root/'work/episode-preparation/packages/key'/self.edition;self.package.mkdir(parents=True);(self.package/'audio.opus').write_bytes(b'fixture audio')
  identity='sha256:'+sha(self.package/'audio.opus')
  write(self.package/'transcript/baseline.json',dict(episode_guid=self.guid,segments=[dict(id=1,text='Mammalia')]))
  write(self.package/'transcript/alignment.json',dict(audio_identity=identity,source_transcript_sha256=sha(self.package/'transcript/baseline.json')))
  artifacts=[dict(file=n,byte_length=(self.package/n).stat().st_size,sha256=sha(self.package/n)) for n in ['audio.opus','transcript/baseline.json','transcript/alignment.json']]
  write(self.package/'episode.json',dict(episode_guid=self.guid,metadata=dict(title='Fixture',number='1'),audio=dict(file='audio.opus',identity=identity,duration_ms=1000),transcript=dict(reviewed_file='transcript/baseline.json',alignment_file='transcript/alignment.json',passage_count=1),artifacts=artifacts))
  self.entry=dict(id='taxon',name='Enriched',kind='fossil',review='suggested',aliases=[],author_ids=[],anchors=[dict(guid=self.guid,edition=self.edition,passage_id=1,passage_text='Mammalia',quote='Mammalia')])
  self.revision=self.root/'work/episode-preparation/index-revisions/key/revision';self.sidecar=self.revision/'index.json'
  write(self.sidecar,dict(schema_version=1,entries=[self.entry]));self.save_summary()
  old=dict(self.entry,name='Stale asset heading');write(self.root/'flutter_app/assets/data/contextual_indexes.json',dict(entries=[old]))
  write(self.root/'work/episode-preparation/library.json',{self.guid:dict(package=str(self.package.relative_to(self.root)),edition=self.edition,index_directory=str(self.revision.relative_to(self.root)))})
  (self.root/'data').mkdir();(self.root/'data/segments.yaml').write_text('segments: []\n')
 def tearDown(self):self.tmp.cleanup()
 def save_summary(self):write(self.sidecar.with_name('summary.json'),dict(episode_guid=self.guid,edition=self.edition,index_sha256=sha(self.sidecar)))
 def export(self):
  old=sys.argv;sys.argv=['export',str(self.root),'--destination',str(self.destination)];scope={'__name__':'fixture'}
  try:exec(compile(source,'export-fixture','exec'),scope)
  finally:
   sys.argv=old
   if 'lock' in scope:scope['lock'].close()
  library=json.loads((self.destination/'library.json').read_text());relative=library['episodes'][0]['files']['indexing/index.json'];return json.loads((self.destination/relative).read_text())
 def test_selected_revision_overrides_stale_asset(self):self.assertEqual(self.export()['entries'][0]['name'],'Enriched')
 def test_rejected_revision_is_not_resurrected_from_global_asset(self):
  self.entry.update(review='rejected');write(self.sidecar,dict(schema_version=1,entries=[self.entry]));self.save_summary();self.assertEqual(self.export()['entries'][0]['review'],'rejected')
 def test_wrong_revision_hash_prevents_publication(self):
  write(self.sidecar.with_name('summary.json'),dict(episode_guid=self.guid,edition=self.edition,index_sha256='wrong'))
  with self.assertRaises(SystemExit):self.export()
  self.assertFalse((self.destination/'library.json').exists())
unittest.main(argv=['enrichment-export-fixtures'],verbosity=2)
PY_TEST

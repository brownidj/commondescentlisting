#!/bin/zsh
# Offline fixtures only. No model, network, application or real package writes.
set -euo pipefail
enrichment_test_project="${0:A:h:h:h}"
exec python3 - "$enrichment_test_project" <<'PY_TEST'
from pathlib import Path
import copy,hashlib,json,sys,tempfile,unittest
from unittest.mock import patch
project=Path(sys.argv[1]);sys.path.insert(0,str(project/'scripts/indexing/lib'))
from enrichment_policy import EnrichmentPolicy,apply_document,sha,enc,write
source=(project/'scripts/enrich_episode_index.zsh').read_text().split("<<'PY_EPISODE_ENRICH'\n",1)[1].rsplit('\nPY_EPISODE_ENRICH',1)[0]
ns={'__name__':'enrichment_fixture'};exec(compile(source,'episode-enrichment-inline','exec'),ns)
class FakePolicy(EnrichmentPolicy):
 calls=0;fail_at=None;outage=False
 def resolve(self,key,group):
  type(self).calls+=1
  if type(self).fail_at==type(self).calls:raise KeyboardInterrupt('fixture cancellation')
  return dict(kind=key[0],name=group[0]['name'],source_ids=[e['id'] for e in group],anchors=group[0]['anchors'],source_anchors=group[0]['anchors'],matched=[],errors=['fixture source unavailable'] if self.outage else [],status='lookup_error' if self.outage else 'applied',reason='fixture identity',target_name=group[0]['name'])
class EpisodeEnrichmentTest(unittest.TestCase):
 def setUp(self):
  self.blacklist_patch=patch('enrichment_policy.load_blacklist',return_value=[]);self.blacklist_patch.start();self.addCleanup(self.blacklist_patch.stop)
  ns['load_blacklist']=lambda root:[]
  self.tmp=tempfile.TemporaryDirectory(dir=project/'work',prefix='enrichment-fixture-');self.base=Path(self.tmp.name);self.package=self.base/'package';(self.package/'transcript').mkdir(parents=True)
  self.index=self.base/'sidecar/index.json';self.index.parent.mkdir();self.summary=self.index.with_name('summary.json');self.output=self.base/'output'
  self.baseline=dict(episode_guid='fixture',segments=[dict(id=1,text='Mammalia and Aves.',start_ms=0,end_ms=1000)])
  write(self.package/'transcript/baseline.json',self.baseline);write(self.package/'episode.json',dict(episode_guid='fixture',metadata=dict(title='Fixture'),transcript=dict(reviewed_file='transcript/baseline.json')))
  anchor=dict(guid='fixture',edition='edition',passage_id=1,passage_text='Mammalia and Aves.',quote='Mammalia')
  self.doc=dict(schema_version=1,entries=[dict(id='one',name='Mammalia',kind='fossil',review='suggested',aliases=[],author_ids=[],anchors=[anchor])])
  write(self.index,self.doc);self.save_summary();self.original=self.index.read_bytes();self.oldsummary=self.summary.read_bytes()
  FakePolicy.calls=0;FakePolicy.fail_at=None;FakePolicy.outage=False;ns['EnrichmentPolicy']=FakePolicy;ns['fingerprint']=lambda root:{'policy':'v1'}
 def tearDown(self):self.tmp.cleanup()
 def save_summary(self):write(self.summary,dict(episode_guid='fixture',edition='edition',index_sha256=sha(self.index.read_bytes()),baseline_sha256=sha((self.package/'transcript/baseline.json').read_bytes())))
 def run_stage(self,*options):return ns['main'](['--package',str(self.package),'--edition','edition','--index',str(self.index),'--output',str(self.output),'--offline',*options])
 def test_checkpoint_reuse_and_policy_invalidation(self):
  self.run_stage();self.run_stage();self.assertEqual(FakePolicy.calls,1)
  ns['fingerprint']=lambda root:{'policy':'v2'};self.run_stage();self.assertEqual(FakePolicy.calls,2)
  self.assertEqual(json.loads(self.summary.read_text())['index_sha256'],sha(self.index.read_bytes()))
 def test_outage_retains_evidence_and_retry_does_not_need_transcription(self):
  FakePolicy.outage=True;result=self.run_stage();self.assertEqual(result['state'],'partial')
  self.assertEqual(json.loads(self.index.read_text())['entries'],self.doc['entries'])
  self.run_stage();self.assertEqual(FakePolicy.calls,1)
  FakePolicy.outage=False;result=self.run_stage('--retry');self.assertEqual(result['state'],'completed');self.assertEqual(FakePolicy.calls,2)
 def test_baseline_change_refuses_stale_sidecar(self):
  self.run_stage();self.baseline['segments'][0]['text']='Changed text.';write(self.package/'transcript/baseline.json',self.baseline)
  with self.assertRaisesRegex(ValueError,'Baseline changed'):self.run_stage()
 def test_cancelled_lookup_reuses_completed_entity_resolution(self):
  second=copy.deepcopy(self.doc['entries'][0]);second.update(id='two',name='Aves');second['anchors'][0]['quote']='Aves';self.doc['entries'].append(second);write(self.index,self.doc);self.save_summary();before=self.index.read_bytes()
  FakePolicy.fail_at=2
  with self.assertRaises(KeyboardInterrupt):self.run_stage()
  self.assertEqual(before,self.index.read_bytes());FakePolicy.fail_at=None;self.run_stage();self.assertEqual(FakePolicy.calls,3)
 def test_cancel_during_two_file_commit_restores_original_pair(self):
  self.output.mkdir();attempt=self.output/'attempts/one';attempt.mkdir(parents=True);before={self.index:self.original,self.summary:self.oldsummary};after={self.index:b'{"new":1}',self.summary:b'{"new":2}'};real_replace=Path.replace
  def replace(path,target):
   if Path(target)==self.summary:raise KeyboardInterrupt('fixture interrupted commit')
   return real_replace(path,target)
  with patch.object(Path,'replace',replace):
   with self.assertRaises(KeyboardInterrupt):ns['publish'](self.index,self.summary,self.output,before,after,{},attempt)
  self.assertEqual(self.index.read_bytes(),self.original);self.assertEqual(self.summary.read_bytes(),self.oldsummary)
 def test_partial_commit_journal_finishes_matching_pair(self):
  attempt=self.output/'attempts/recover';attempt.mkdir(parents=True);after={self.index:b'{"new":1}',self.summary:b'{"new":2}'};cp=dict(attempt='attempts/recover',summary={})
  tx=dict(index_path=str(self.index),summary_path=str(self.summary),checkpoint=cp)
  for target,key in [(self.index,'index'),(self.summary,'summary')]:
   f=attempt/(key+'-after.json');f.write_bytes(after[target]);tx.update({key+'_file':str(f.relative_to(self.output)),key+'_before':sha(target.read_bytes()),key+'_after':sha(after[target])})
  write(attempt/'results.json',{});write(self.output/'transaction.json',tx);self.index.write_bytes(after[self.index]);ns['recover'](self.index,self.summary,self.output)
  self.assertEqual(self.summary.read_bytes(),after[self.summary]);self.assertFalse((self.output/'transaction.json').exists())
 def test_shared_policy_reclassifies_paleocontinent_and_preserves_rejected(self):
  doc=copy.deepcopy(self.doc);doc['entries'][0].update(name='Gondwana',kind='author');doc['entries'][0]['anchors'][0].update(quote='Gondwana',passage_text='Gondwana')
  rejected=copy.deepcopy(doc['entries'][0]);rejected.update(id='rejected',review='rejected');doc['entries'].append(rejected)
  policy=EnrichmentPolicy(project,{('fixture','edition'):{1:'Gondwana'}},False);row=policy.resolve(('author','gondwana'),[doc['entries'][0]])
  updated,changes,merges=apply_document(doc,[row],policy);self.assertEqual(updated['entries'][0]['kind'],'place');self.assertEqual(updated['entries'][1],rejected)
 def test_external_confirmation_is_bound_to_source_identity_and_evidence(self):
  from enrichment_policy import externally_confirmed
  policy=EnrichmentPolicy(project,{('fixture','edition'):{1:'Mammalia and Aves.'}},False)
  row=dict(kind='fossil',name='Mammalia',status='applied',errors=[],matched=[dict(provider='pbdb',record=dict(name='Mammalia',url='https://paleobiodb.org/classic/basicTaxonInfo?taxon_no=1'),retrieved_at_utc='fixture')],reason='Exact scientific identity')
  updated,_,_=apply_document(self.doc,[row],policy);e=updated['entries'][0]
  self.assertTrue(externally_confirmed(e));self.assertEqual(e['review'],'suggested')
  e['name']='Listener edit';self.assertFalse(externally_confirmed(e))
if __name__=='__main__':unittest.main(argv=['episode-enrichment-fixtures'],verbosity=2)
PY_TEST

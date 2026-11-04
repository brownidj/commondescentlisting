#!/bin/zsh
# Offline fixtures only: never sends an API request or touches live packages.
set -euo pipefail
refinement_test_root="${0:A:h:h:h}"
exec "${EPISODE_PYTHON:-${refinement_test_root}/work/whisperx-trial/venv/bin/python}" - "$refinement_test_root" <<'PY_TEST'
from pathlib import Path
import copy,io,json,sys,tempfile,unittest,urllib.error
project=Path(sys.argv[1]);source=(project/'scripts/refine_episode_index.zsh').read_text().split("<<'PY_REFINE'\n",1)[1].rsplit('\nPY_REFINE',1)[0]
ns={'__name__':'offline_refinement_test'};exec(compile(source,'refinement-inline','exec'),ns)
config=json.loads((project/'scripts/indexing_trial/refinement.json').read_text())
def entry(ident,name,kind='author',pid=1,review='suggested'):
 text='Didelphys virginiana and another species.' if pid==1 else 'Other words.'
 return dict(id=ident,name=name,kind=kind,review=review,aliases=[name],subtype='',year=None,publication='',doi='',url='',link_verified=False,author_ids=[],anchors=[dict(guid='guid',edition='edition',passage_id=pid,passage_text=text,quote=name)],note='Offline suggestion.',details={})
def review(cid,action='recategorise',category='Taxonomy',merge=None):
 return dict(id=cid,action=action,category=category,normalized_name=None,merge_into=merge,confidence='high',reason='Species, not an author.',evidence_passage_ids=[1])
class RefinementTest(unittest.TestCase):
 def setUp(self):
  self.index=dict(schema_version=1,entries=[entry('one','Didelphys virginiana')]);self.base=dict(episode_guid='guid',segments=[dict(id=1,text='Didelphys virginiana and another species.')])
  self.req,self.candidates,self.mapping,self.ceiling=ns['prepare_request'](self.index,self.base,'edition','Episode',config)
 def test_bounded_request_and_categories(self):
  self.assertLess(self.ceiling,.5);self.assertEqual(self.req['model'],'gpt-5.4-mini-2026-03-17');self.assertFalse(self.req['store']);self.assertNotIn('tools',self.req)
  self.assertEqual(self.candidates[0]['categories'],['Authors'])
 def test_species_recategorisation_preserves_literal_evidence(self):
  rows=ns['validate']({'reviews':[review(1)]},self.candidates)
  result,summary=ns['apply_review'](self.index,rows,self.mapping,config['model']);e=result['entries'][0]
  self.assertEqual(e['kind'],'fossil');self.assertEqual(e['review'],'suggested');self.assertEqual(e['anchors'],self.index['entries'][0]['anchors']);self.assertEqual(json.loads(e['details']['refinement_source'])['kind'],'author');self.assertEqual(summary['applied'],1)
 def test_uncertain_and_low_confidence_remain_unchanged(self):
  for r in [dict(review(1),action='uncertain',category=None),dict(review(1),confidence='low')]:
   result,_=ns['apply_review'](self.index,{1:r},self.mapping,config['model']);self.assertEqual(result,self.index)
 def test_rejects_invalid_coverage_evidence_and_types(self):
  for rows in [[],[review(1),review(1)],[review(2)],[dict(review(1),evidence_passage_ids=[2])],[dict(review(1),normalized_name='x'*1001)],[dict(review(1),merge_into=2)]]:
   with self.assertRaises(ValueError):ns['validate']({'reviews':rows},self.candidates)
 def test_human_decisions_not_submitted(self):
  self.index['entries'][0]['review']='confirmed'
  _,cs,_,_=ns['prepare_request'](self.index,self.base,'edition','Episode',config);self.assertEqual(cs,[])
 def confirm(self,e):
  from enrichment_policy import confirmation_evidence
  e['details']['external_confirmation']=json.dumps(dict(status='confirmed',name=e['name'],kind=e['kind'],sources=['pbdb'],evidence=confirmation_evidence(e)))
 def test_external_confirmed_items_are_not_sent_or_changed(self):
  self.confirm(self.index['entries'][0])
  _,cs,mapping,_=ns['prepare_request'](self.index,self.base,'edition','Episode',config);self.assertEqual(cs,[]);self.assertEqual(mapping,{})
  with self.assertRaisesRegex(ValueError,'externally confirmed'):ns['apply_review'](self.index,{1:review(1)},{1:'one'},config['model'])
 def test_stale_confirmation_does_not_exclude_changed_metadata(self):
  self.confirm(self.index['entries'][0]);self.index['entries'][0]['name']='Changed heading'
  _,cs,_,_=ns['prepare_request'](self.index,self.base,'edition','Episode',config);self.assertEqual(len(cs),1)
 def test_only_unconfirmed_items_enter_payload(self):
  self.confirm(self.index['entries'][0]);second=entry('two','another species','fossil');self.index['entries'].append(second)
  request,cs,mapping,_=ns['prepare_request'](self.index,self.base,'edition','Episode',config)
  self.assertEqual([c['name'] for c in cs],['another species']);self.assertEqual(mapping,{1:'two'})
 def test_all_confirmed_needs_no_key_or_network(self):
  self.confirm(self.index['entries'][0])
  with tempfile.TemporaryDirectory(dir=project/'work') as temp:
   root=Path(temp);(root/'scripts/indexing_trial').mkdir(parents=True);(root/'scripts/indexing_trial/refinement.json').write_text(json.dumps(config))
   pkg=root/'package';(pkg/'indexing').mkdir(parents=True);(pkg/'transcript').mkdir();base=ns['encoded'](self.base)
   (pkg/'indexing/index.json').write_bytes(ns['encoded'](self.index));(pkg/'transcript/baseline.json').write_bytes(base)
   (pkg/'episode.json').write_text(json.dumps(dict(transcript=dict(reviewed_file='transcript/baseline.json'))))
   (pkg/'indexing/summary.json').write_text(json.dumps(dict(index_sha256=ns['sha']((pkg/'indexing/index.json').read_bytes()),baseline_sha256=ns['sha'](base),edition='edition',episode_guid='guid',title='Episode')))
   old=sys.argv;sys.argv=['refine',str(root),'--package',str(pkg),'--edition','edition','--output',str(root/'out')]
   try:ns['main']()
   finally:sys.argv=old
   self.assertEqual(json.loads((root/'out/result.json').read_text())['paid_requests'],0);self.assertFalse((root/'out/request-started.json').exists())
 def test_evidence_mismatch_stops_request(self):
  self.index['entries'][0]['anchors'][0]['edition']='other'
  with self.assertRaises(ValueError):ns['prepare_request'](self.index,self.base,'edition','Episode',config)
 def test_merge_cycles_and_category_conflicts_rejected(self):
  cs=[self.candidates[0],dict(self.candidates[0],id=2)]
  for rows in [[review(1,'merge',merge=2),review(2,'merge',merge=1)],[review(1,'merge',merge=2),review(2,category='Authors')]]:
   with self.assertRaises(ValueError):ns['validate']({'reviews':rows},cs)
 def test_budget_and_no_retry_guard_before_network(self):
  with tempfile.TemporaryDirectory(dir=project/'work') as temp:
   root=Path(temp);(root/'scripts/indexing_trial').mkdir(parents=True);(root/'work/indexing-trial').mkdir(parents=True)
   key=root/'work/indexing-trial/openai-api-key';key.write_text('fake-fixture-credential');key.chmod(0o600)
   pkg=root/'package';(pkg/'indexing').mkdir(parents=True);(pkg/'transcript').mkdir();out=root/'out';out.mkdir()
   (pkg/'indexing/index.json').write_bytes(ns['encoded'](self.index));base=ns['encoded'](self.base);(pkg/'transcript/baseline.json').write_bytes(base)
   (pkg/'episode.json').write_text(json.dumps(dict(transcript={'reviewed_file':'transcript/baseline.json'})))
   summary=dict(index_sha256=ns['sha']((pkg/'indexing/index.json').read_bytes()),baseline_sha256=ns['sha'](base),edition='edition',episode_guid='guid',title='Episode');(pkg/'indexing/summary.json').write_text(json.dumps(summary))
   oldargs=sys.argv;oldurl=ns['urllib'].request.urlopen
   def forbidden(*a,**kw):raise AssertionError('Network must not be called by these fixtures')
   ns['urllib'].request.urlopen=forbidden
   try:
    sys.argv=['refine',str(root),'--package',str(pkg),'--edition','edition','--output',str(out)]
    huge=dict(config,max_output_tokens=1000000);(root/'scripts/indexing_trial/refinement.json').write_text(json.dumps(huge))
    with self.assertRaisesRegex(ValueError,'exceeds'):ns['main']()
    self.assertFalse((out/'request-started.json').exists())
    (root/'scripts/indexing_trial/refinement.json').write_text(json.dumps(config));(out/'request-started.json').write_text('{}')
    with self.assertRaisesRegex(ValueError,'already started'):ns['main']()
    (out/'request-started.json').unlink()
    def denied(*a,**kw):raise urllib.error.HTTPError('https://api.openai.com/v1/responses',401,'Unauthorized',{},io.BytesIO(json.dumps({'error':{'code':'invalid_api_key','type':'authentication_error','message':'fake-fixture-credential'}}).encode()))
    ns['urllib'].request.urlopen=denied
    original=(pkg/'indexing/index.json').read_bytes()
    with self.assertRaisesRegex(ValueError,'rejected'):ns['main']()
    self.assertEqual((pkg/'indexing/index.json').read_bytes(),original)
    self.assertNotIn('fake-fixture-credential',(out/'api-error.json').read_text())
    (out/'request-started.json').unlink()
    result=dict(status='completed',usage={'input_tokens':100,'input_tokens_details':{'cached_tokens':0},'output_tokens':100},output=[{'content':[{'type':'output_text','text':json.dumps({'reviews':[review(1)]})}]}])
    class Response(io.BytesIO):
     def __init__(self):super().__init__(json.dumps(result).encode())
    ns['urllib'].request.urlopen=lambda *a,**kw:Response()
    ns['main']()
    revised=json.loads((pkg/'indexing/index.json').read_text());self.assertEqual(revised['entries'][0]['kind'],'fossil')
    self.assertEqual(json.loads((pkg/'indexing/summary.json').read_text())['index_sha256'],ns['sha']((pkg/'indexing/index.json').read_bytes()))
    self.assertTrue((out/'index-before.json').exists());self.assertTrue((out/'usage.json').exists())

   finally:sys.argv=oldargs;ns['urllib'].request.urlopen=oldurl
unittest.main(argv=['index-refinement-tests'])
PY_TEST

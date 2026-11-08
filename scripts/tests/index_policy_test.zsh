#!/bin/zsh
# Offline fixtures; no production data, models or external API requests.
set -euo pipefail
policy_project="${0:A:h:h:h}"
exec python3 - "$policy_project" <<'PY_TEST'
from pathlib import Path
import copy,json,sys,tempfile,unittest
root=Path(sys.argv[1]);sys.path.insert(0,str(root/'scripts/indexing/lib'))
from index_policy import heading,blocked,apply_blacklist,load_blacklist,merge_blacklist,recover_publications
class PolicyTest(unittest.TestCase):
 def entry(self,ident='old',name='The Example',kind='place',deleted=False):
  return dict(id=ident,name=name,kind=kind,aliases=['An old alias'],variant_ids=['merged'],deleted=deleted)
 def test_heading_preserves_case_and_is_idempotent(self):
  for before,after in [('The Example','Example'),('the example','example'),('Example, The','Example'),('Therapsida','Therapsida'),('The','The')]:
   self.assertEqual(heading(before),after);self.assertEqual(heading(after),after)
 def test_changed_ids_names_aliases_and_category_boundaries(self):
  records=[self.entry(deleted=True)]
  self.assertTrue(blocked(dict(self.entry('new','example, the'),variant_ids=[]),records))
  self.assertTrue(blocked(dict(self.entry('new','An old alias'),variant_ids=[]),records))
  self.assertTrue(blocked(self.entry('merged','Renamed','author'),records))
  self.assertFalse(blocked(dict(self.entry('new','The Example','paper'),variant_ids=[]),records))
  self.assertFalse(blocked(dict(self.entry('new','Example Island'),variant_ids=[]),records))
 def test_blacklist_only_matches_target_heading_not_a_generic_alias(self):
  deleted=dict(self.entry(deleted=True),name='A publication',aliases=['study'],variant_ids=[])
  candidate=dict(self.entry('new','Study attributed to Someone et al.','paper'),aliases=['study'],variant_ids=[])
  self.assertFalse(blocked(candidate,[deleted]))
 def test_append_only_ledger_and_tombstone_application(self):
  with tempfile.TemporaryDirectory() as temp:
   path=Path(temp);document=dict(schema_version=1,entries=[self.entry(deleted=True)])
   merge_blacklist(path,document);merge_blacklist(path,document)
   self.assertEqual(len(load_blacklist(path)),1)
   merge_blacklist(path,dict(schema_version=1,entries=[]))
   candidate=dict(self.entry('new'),variant_ids=[])
   result,count=apply_blacklist(dict(entries=[candidate]),load_blacklist(path))
   self.assertEqual(count,1);self.assertTrue(result['entries'][0]['deleted']);self.assertFalse(candidate['deleted'])
 def reference(self,text,context=None):
  baseline={('guid','edition'):{1:text,2:'Neighbor passage.'}}
  anchor=dict(guid='guid',edition='edition',passage_id=1,passage_text=text,quote='study')
  doc=dict(schema_version=1,entries=[],unidentified_reference_mentions=[dict(id='mention:1',anchors=[anchor],context=context or [dict(id=1,text=text)])])
  return doc,baseline
 def test_attributed_reference_is_visible_and_idempotent(self):
  doc,base=self.reference('This is a study by Tissier et al. in PeerJ.')
  recovered,count=recover_publications(doc,base);self.assertEqual(count,1)
  self.assertEqual(recovered['entries'][0]['name'],'Study attributed to Tissier et al.')
  self.assertEqual(recovered['entries'][0]['kind'],'paper');self.assertEqual(recovered['entries'][0]['review'],'suggested')
  again,count=recover_publications(recovered,base);self.assertEqual(count,0);self.assertEqual(recovered,again)
 def test_generic_and_stale_references_are_not_claimed_publications(self):
  doc,base=self.reference('One study does not prove anything.')
  recovered,count=recover_publications(doc,base);self.assertEqual(count,0);self.assertEqual(recovered['entries'],[])
  doc,base=self.reference('This study by Someone et al. in a journal.')
  base[('guid','edition')][1]='Corrected passage.'
  self.assertEqual(recover_publications(doc,base)[1],0)
 def test_attribution_in_neighbor_is_used_with_exact_evidence(self):
  text='This study was published in';context=[dict(id=1,text=text),dict(id=2,text='PeerJ by Butler et al.')]
  doc,base=self.reference(text,context);base[('guid','edition')][2]=context[1]['text']
  recovered,_=recover_publications(doc,base);e=recovered['entries'][0]
  self.assertEqual(e['name'],'Study attributed to Butler et al.')
  self.assertEqual({a['passage_id'] for a in e['anchors']},{1,2})
if __name__=='__main__':unittest.main(argv=['index-policy-fixtures'],verbosity=2)
PY_TEST

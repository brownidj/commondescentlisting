#!/bin/zsh
# Isolated fixtures: no network, credentials, live registry or package changes.
set -euo pipefail
crossref_test_project="${0:A:h:h:h}"
exec python3 - "$crossref_test_project" <<'PY_TEST'
from pathlib import Path
import copy,json,sys,tempfile,unittest
from types import SimpleNamespace
root=Path(sys.argv[1]);sys.path.insert(0,str(root/'scripts/indexing/lib'))
from crossref_publications import context_match,resolve_publication,attach_authors,valid_dates
from enrichment_policy import helpers

class CrossrefTest(unittest.TestCase):
 def setUp(self):
  self.c=dict(title='Exceptional soft tissues preservation in an Eocene salamander',doi='10.1234/example',authors=[dict(given='Jane',family='Tissier')],journal='PeerJ',crossref_type='journal-article',dates={'published':[[2017,10,3]]})
  self.text='This study by Tissier et al. in Pier J. describes exceptional soft tissues in a fossil salamander.'
 def test_corroborated_context_requires_independent_clues(self):
  self.assertIsNotNone(context_match(self.c,self.text,'2017-10-22'))
  self.assertIsNone(context_match(self.c,self.text.replace('Tissier','Smith'),'2017-10-22'))
  self.assertIsNone(context_match(self.c,self.text.replace('Pier J','Nature'),'2017-10-22'))
  self.assertIsNone(context_match(self.c,self.text,'2016-10-22'))
  self.assertIsNone(context_match(dict(self.c,title='Author Correction: '+self.c['title']),self.text,'2017-10-22'))
 def test_invalid_date_parts_are_not_invented(self):
  self.assertEqual(valid_dates(dict(dates={'issued':[[None]]})),[])
 def test_ambiguous_context_does_not_confirm_first_search_hit(self):
  with tempfile.TemporaryDirectory() as temp:
   anchor=dict(guid='g',edition='e',passage_id=1,passage_text=self.text,quote='study')
   e=dict(name='Study attributed to Tissier et al.',subtype='unidentified_publication',anchors=[anchor])
   records=[dict(DOI='10.1234/a',title=[self.c['title']],author=[dict(given='Jane',family='Tissier')],type='journal-article',**{'container-title':['PeerJ'],'published':{'date-parts':[[2017,10,3]]}}),dict(DOI='10.1234/b',title=['Exceptional soft tissues preservation in another salamander'],author=[dict(given='Jane',family='Tissier')],type='journal-article',**{'container-title':['PeerJ'],'published':{'date-parts':[[2017,10,3]]}})]
   cr=helpers(root,'lookup_crossref.zsh','PY_CROSSREF')
   policy=SimpleNamespace(root=Path(temp),baselines={('g','e'):{1:self.text}},publication_cutoff='2017-10-22',valid_anchors=lambda _: [anchor],cr=cr,fetch=lambda *a:dict(payload={'message':{'items':records}},retrieved_at_utc='fixture',request_url='https://api.crossref.org/works'))
   result=resolve_publication(policy,[e],[anchor]);self.assertEqual(result['status'],'hard_unresolved');self.assertEqual(len(result['candidates']),2)
 def test_full_author_order_and_blacklist_preserve_bibliography(self):
  authors=[dict(given='Jane',family='Tissier'),dict(given='John',family='Other')]
  anchor=dict(guid='g',edition='e',passage_id=1,passage_text=self.text,quote='study')
  citation=dict(self.c,status='source_confirmed',authors=authors,url='https://doi.org/10.1234/example')
  pub=dict(id='paper',kind='paper',name=self.c['title'],anchors=[anchor],details={'bibliography':json.dumps(citation)})
  document={'entries':[pub]};confirmed={}
  attach_authors(document,confirmed,lambda e:e['anchors'],lambda e:False)
  self.assertEqual([e['name'] for e in document['entries'][1:]],['Jane Tissier','John Other'])
  self.assertEqual(pub['author_ids'],[e['id'] for e in document['entries'][1:]])
  self.assertIn('may not be spoken',document['entries'][1]['note'])
  attach_authors(document,confirmed,lambda e:e['anchors'],lambda e:False)
  self.assertEqual(len(document['entries']),3)
  blocked_doc={'entries':[dict(pub,author_ids=[])]}
  attach_authors(blocked_doc,{},lambda e:e['anchors'],lambda e:e['name']=='John Other')
  self.assertEqual(len(blocked_doc['entries']),2)
  self.assertEqual(len(json.loads(blocked_doc['entries'][0]['details']['bibliography'])['authors']),2)
if __name__=='__main__':unittest.main(argv=['crossref-enrichment-fixtures'],verbosity=2)
PY_TEST

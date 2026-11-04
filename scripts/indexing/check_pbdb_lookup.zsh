#!/bin/zsh
# Offline PBDB fixtures; no changes to real indexes or remote requests.
set -euo pipefail
pbdb_fixture_project="${0:A:h:h:h}"
exec python3 - "$pbdb_fixture_project" <<'PY'
from pathlib import Path
import contextlib,hashlib,io,json,sys,tempfile,unittest,urllib.parse
from unittest.mock import patch
source=(Path(sys.argv[1])/'scripts/indexing/lookup_pbdb.zsh').read_text().split("<<'PY_PBDB'\n",1)[1].rsplit('\nPY_PBDB',1)[0]
ns={'__name__':'fixture'};exec(compile(source,'pbdb-fixture','exec'),ns)
class PBDB(unittest.TestCase):
    def test_bounded_non_wildcard_query(self):
        url=ns['query_url']({'name':'Thylacoleo carnifex'});parsed=urllib.parse.urlparse(url)
        self.assertEqual(parsed.hostname,'paleobiodb.org');params=urllib.parse.parse_qs(parsed.query)
        self.assertEqual(params['limit'],['5']);self.assertEqual(params['taxon_status'],['all'])
        for name in ['A','Smilodon%','taxon_name','Taxon&all_records']:
            with self.assertRaises(ValueError):ns['query_url']({'name':name})
    def test_synonym_and_rank_evidence_are_not_confirmation(self):
        record=dict(taxon_no='123',orig_no='122',taxon_name='Oldus example',taxon_rank='species',accepted_no='456',accepted_name='Newus example',accepted_rank='species',taxon_attr='Author 1900',is_extant='extinct',firstapp_max_ma=10)
        item=ns['metadata'](record,'Oldus example')
        self.assertEqual(item['name'],'Oldus example');self.assertEqual(item['accepted_name'],'Newus example')
        self.assertTrue(item['exact_query_name']);self.assertFalse(item['mention_confirmed'])
        self.assertEqual(item['recorded_occurrence_range']['firstapp_max_ma'],10)
        self.assertNotIn('confidence',item)
    def test_common_name_is_not_an_exact_scientific_match(self):
        item=ns['metadata'](dict(taxon_no='1',taxon_name='Macropodidae',taxon_rank='family'),'kangaroos')
        self.assertFalse(item['exact_query_name']);self.assertEqual(item['review_status'],'requires_review')
    def test_cache_no_match_and_stale_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);index=root/'index.json';base=root/'baseline.json';plan=root/'plan.json';out=root/'out'
            anchor=dict(guid='g',edition='edition',passage_id=1,passage_text='Kangaroos hop.',quote='Kangaroos')
            index.write_text(json.dumps(dict(schema_version=1,entries=[dict(id='taxon',kind='fossil',name='kangaroos',review='suggested',anchors=[anchor])])));before=index.read_bytes()
            base.write_text(json.dumps(dict(episode_guid='g',segments=[dict(id=1,text='Kangaroos hop.')])) )
            query=dict(id='q',source_ids=['taxon'],name='kangaroos')
            plan.write_text(json.dumps(dict(schema_version=1,episode_guid='g',edition='edition',index_sha256=hashlib.sha256(index.read_bytes()).hexdigest(),baseline_sha256=hashlib.sha256(base.read_bytes()).hexdigest(),queries=[query])))
            url=ns['query_url'](query);cache=root/'work/pbdb-cache';cache.mkdir(parents=True)
            (cache/(hashlib.sha256(url.encode()).hexdigest()+'.json')).write_text(json.dumps(dict(request_url=url,retrieved_at_utc='fixture',payload=dict(records=[],warnings=['No matching names']))))
            args=['fixture',str(root),'--index',str(index),'--baseline',str(base),'--plan',str(plan),'--output',str(out)]
            with patch.object(sys,'argv',args),patch('urllib.request.urlopen',side_effect=AssertionError('Unexpected network')) as network,contextlib.redirect_stdout(io.StringIO()):
                ns['main']();network.assert_not_called();d=json.loads((out/'results.json').read_text())
                self.assertEqual(d['requests_sent'],0);self.assertEqual(d['results'][0]['status'],'unresolved')
                self.assertFalse(d['published_index_modified']);self.assertEqual(index.read_bytes(),before)
                base.write_text('{}')
                with self.assertRaises(ValueError):ns['main']()
unittest.main(argv=['offline-pbdb'],verbosity=2)
PY

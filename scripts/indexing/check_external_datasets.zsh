#!/bin/zsh
# Offline provider parsing/evidence fixtures; no requests or real index changes.
set -euo pipefail
external_fixture_project="${0:A:h:h:h}"
exec python3 - "$external_fixture_project" <<'PY'
from pathlib import Path
import contextlib,hashlib,io,json,sys,tempfile,unittest,urllib.parse
from unittest.mock import patch
source=(Path(sys.argv[1])/'scripts/indexing/lookup_external_datasets.zsh').read_text().split("<<'PY_EXTERNAL'\n",1)[1].rsplit('\nPY_EXTERNAL',1)[0]
ns={'__name__':'fixture'};exec(compile(source,'external-fixtures','exec'),ns)
class External(unittest.TestCase):
    def test_col_release_is_pinned(self):
        with self.assertRaises(ValueError):ns['query_url']('col',{'name':'Didelphis virginiana'},'3LR')
        url=ns['query_url']('col',{'name':'Didelphis virginiana'},316595)
        self.assertIn('/316595/',url)
    def test_col_candidates_are_not_confirmation(self):
        rows=ns['col_candidates']({'usage':{'id':'a','name':'Testus example','rank':'species','status':'synonym'},'match':False,'type':'fuzzy','issues':{'homonym':'ambiguous'},'alternatives':[{'id':'b','name':'Testus example','rank':'species'}]},123)
        self.assertEqual(len(rows),2);self.assertFalse(rows[0]['service_match']);self.assertEqual(rows[0]['review_status'],'requires_review')
        self.assertEqual(rows[0]['status'],'synonym')
    def test_geo_ambiguous_regions_and_coverage(self):
        regions='US.MT\tMontana\tMontana\t5667009\nBG.47\tMontana\tMontana\t729561\nCN.19\tLiaoning Sheng\tLiaoning Sheng\t2036115'
        records=ns['geo_records']('',regions)
        self.assertEqual(len(ns['geo_matches'](records,{'name':'Montana'})),2)
        self.assertEqual(len(ns['geo_matches'](records,{'name':'Montana','country':'US'})),1)
        self.assertEqual(ns['geo_matches'](records,{'name':'Gondwana'}),[])
        self.assertEqual(ns['geo_matches'](records,{'name':'Liaoning'})[0]['match_type'],'region name prefix')
    def test_macro_interval_is_not_place(self):
        rows=ns['macro_candidates']({'success':{'license':'CC-BY 4.0','data':[{'int_id':21,'name':'Oligocene','b_age':33.9,'t_age':23.04,'int_type':'epoch'}]}},'https://macrostrat.org/api/v2/defs/intervals?name=Oligocene')
        self.assertEqual(rows[0]['kind'],'geologic interval');self.assertEqual(rows[0]['base_age_ma'],33.9)
        with self.assertRaises(ValueError):ns['macro_candidates']({'success':{'options':{}}},'url')
    def test_offline_cache_and_stale_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);index=root/'index.json';base=root/'baseline.json';plan=root/'plan.json';out=root/'out'
            anchor=dict(guid='g',edition='e',passage_id=1,passage_text='Oligocene rocks.',quote='Oligocene')
            index.write_text(json.dumps(dict(schema_version=1,entries=[dict(id='i',kind='place',name='Oligocene',anchors=[anchor])])));prior=index.read_bytes()
            base.write_text(json.dumps(dict(episode_guid='g',segments=[dict(id=1,text='Oligocene rocks.')])));q=dict(id='q',source_ids=['i'],name='Oligocene',kind='interval')
            plan.write_text(json.dumps(dict(schema_version=1,provider='macrostrat',episode_guid='g',edition='e',index_sha256=hashlib.sha256(prior).hexdigest(),baseline_sha256=hashlib.sha256(base.read_bytes()).hexdigest(),queries=[q])))
            url=ns['query_url']('macrostrat',q);cache=root/'work/external-datasets-cache';cache.mkdir(parents=True)
            (cache/(hashlib.sha256(url.encode()).hexdigest()+'.json')).write_text(json.dumps(dict(request_url=url,retrieved_at_utc='fixture',payload={'success':{'license':'CC-BY 4.0','data':[]}})))
            argv=['fixture',str(root),'--provider','macrostrat','--index',str(index),'--baseline',str(base),'--plan',str(plan),'--output',str(out)]
            with patch.object(sys,'argv',argv),patch('urllib.request.urlopen',side_effect=AssertionError('Network forbidden')) as network,contextlib.redirect_stdout(io.StringIO()):
                ns['main']();network.assert_not_called();report=json.loads((out/'results.json').read_text())
                self.assertEqual(report['requests_sent'],0);self.assertEqual(report['outcomes']['unresolved'],1);self.assertEqual(index.read_bytes(),prior)
                base.write_text('{}')
                with self.assertRaises(ValueError):ns['main']()
unittest.main(argv=['offline-external'],verbosity=2)
PY

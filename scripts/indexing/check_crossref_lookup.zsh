#!/bin/zsh
# Offline fixtures: no Crossref service or changes to real indexes.
set -euo pipefail
crossref_fixture_project="${0:A:h:h:h}"
exec python3 - "$crossref_fixture_project" <<'PY'
from pathlib import Path
import contextlib,hashlib,io,json,sys,tempfile,unittest,urllib.parse
from unittest.mock import patch
project=Path(sys.argv[1]);script=project/'scripts/indexing/lookup_crossref.zsh'
source=script.read_text().split("<<'PY_CROSSREF'\n",1)[1].rsplit('\nPY_CROSSREF',1)[0]
ns={'__name__':'fixture'};exec(compile(source,str(script),'exec'),ns)
class Crossref(unittest.TestCase):
    def test_query_controls(self):
        url=ns['query_url']({'query':'Mastodon climate','author':'An Author','strict_publication_cutoff':True},'2020-09-20')
        params=urllib.parse.parse_qs(urllib.parse.urlparse(url).query)
        self.assertEqual(params['query.author'],['An Author'])
        self.assertEqual(params['filter'],['until-pub-date:2020-09-20'])
        advisory=ns['query_url']({'query':'Air breathing sea scorpion'},'2020-09-20')
        self.assertNotIn('filter',urllib.parse.parse_qs(urllib.parse.urlparse(advisory).query))
        late=ns['metadata']({'title':['Online-first paper'],'published':{'date-parts':[[2020,11]]}},'2020-09-20')
        self.assertIn('after the episode',late['publication_date_note'])
        self.assertEqual(urllib.parse.urlparse(url).hostname,'api.crossref.org')
        with self.assertRaises(ValueError):ns['query_url']({'query':'study'},'')
        with self.assertRaises(ValueError):ns['query_url']({'doi':'https://invalid.example'},'')
    def test_score_is_not_confirmation(self):
        r=ns['metadata'](dict(title=['Fixture'],DOI='10.1234/example',author=[dict(given='First',family='Last')],published={'date-parts':[[2020,9,1]]},type='journal-article',score=75))
        self.assertEqual(r['status'],'candidate_requires_review');self.assertEqual(r['crossref_relevance_score'],75)
        self.assertEqual(r['dates']['published'],[[2020,9,1]]);self.assertNotIn('confidence',r)
    def test_offline_replay_and_stale_plan(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);index=root/'index.json';base=root/'baseline.json';plan=root/'plan.json';out=root/'out'
            baseline=dict(episode_guid='g',segments=[dict(id=1,text='The paper by First Last.')])
            anchor=dict(guid='g',edition='edition',passage_id=1,passage_text=baseline['segments'][0]['text'],quote='paper')
            index.write_text(json.dumps(dict(schema_version=1,entries=[],unidentified_reference_mentions=[dict(id='m',anchors=[anchor])])))
            base.write_text(json.dumps(baseline));q=dict(id='q',source_id='m',query='Specific fixture paper',passage_ids=[1])
            plan.write_text(json.dumps(dict(schema_version=1,episode_guid='g',edition='edition',index_sha256=hashlib.sha256(index.read_bytes()).hexdigest(),baseline_sha256=hashlib.sha256(base.read_bytes()).hexdigest(),queries=[q])))
            url=ns['query_url'](q,'');cache=root/'work/crossref-cache';cache.mkdir(parents=True)
            (cache/(hashlib.sha256(url.encode()).hexdigest()+'.json')).write_text(json.dumps(dict(request_url=url,retrieved_at_utc='fixture',payload=dict(status='ok',message=dict(items=[dict(title=['Fixture'],DOI='10.1234/test')])))))
            args=['fixture',str(root),'--index',str(index),'--baseline',str(base),'--plan',str(plan),'--output',str(out)]
            with patch.object(sys,'argv',args),patch('urllib.request.urlopen',side_effect=AssertionError('Unexpected HTTP')) as network,contextlib.redirect_stdout(io.StringIO()):
                ns['main']();network.assert_not_called();d=json.loads((out/'results.json').read_text())
                self.assertEqual(d['requests_sent'],0);self.assertFalse(d['results'][0]['mention_confirmed']);self.assertTrue(d['results'][0]['cache_hit'])
                self.assertEqual(json.loads(index.read_text())['entries'],[])
                base.write_text(json.dumps(dict(baseline,segments=[])))
                with self.assertRaises(ValueError):ns['main']()
unittest.main(argv=['offline-crossref'],verbosity=2)
PY

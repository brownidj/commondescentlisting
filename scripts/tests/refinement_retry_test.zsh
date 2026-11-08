#!/bin/zsh
# Isolated transport/revision fixtures. Never contacts an API or reads a key.
set -euo pipefail
retry_test_project="${0:A:h:h:h}"
exec "${EPISODE_PYTHON:-${retry_test_project}/work/whisperx-trial/venv/bin/python}" - "$retry_test_project" <<'PY_TEST'
from pathlib import Path
import json,ssl,sys,tempfile,unittest,urllib.error
root=Path(sys.argv[1]);sys.path.insert(0,str(root/'scripts/indexing/lib'))
from refinement_transport import tls_context,connection_problem
from refinement_retry import stage_retry,activate_retry,atomic,digest,load
class RetryTest(unittest.TestCase):
 def test_tls_certificate_and_hostname_verification_remain_enabled(self):
  context=tls_context();self.assertEqual(context.verify_mode,ssl.CERT_REQUIRED);self.assertTrue(context.check_hostname);self.assertGreater(len(context.get_ca_certs()),0)
 def test_certificate_error_has_safe_diagnostics(self):
  error=urllib.error.URLError(ssl.SSLCertVerificationError(1,'fake-sensitive-message'))
  report=connection_problem(error,'connecting','fixture-client')
  self.assertEqual(report['category'],'tls_certificate_error');self.assertFalse(report['possible_billable_request'])
  self.assertNotIn('fake-sensitive-message',json.dumps(report))
 def test_response_timeout_preserves_billing_uncertainty(self):
  report=connection_problem(TimeoutError(),'reading_response','client','request')
  self.assertEqual(report['category'],'timeout');self.assertTrue(report['possible_billable_request']);self.assertEqual(report['request_id'],'request')
 def setup_package(self,project):
  package=project/'work/episode-preparation/packages/key/edition';(package/'transcript').mkdir(parents=True);(package/'indexing').mkdir()
  atomic(package/'transcript/baseline.json',dict(episode_guid='guid',segments=[]))
  atomic(package/'episode.json',dict(episode_guid='guid',transcript=dict(reviewed_file='transcript/baseline.json')))
  atomic(package/'indexing/index.json',dict(schema_version=1,entries=[]))
  atomic(package/'indexing/summary.json',dict(episode_guid='guid',edition='edition',baseline_sha256=digest(package/'transcript/baseline.json'),index_sha256=digest(package/'indexing/index.json')))
  library=project/'work/episode-preparation/library.json';atomic(library,{'guid':dict(key='key',edition='edition',package=str(package.relative_to(project)),model='medium.en')})
  return package,library
 def test_partial_revision_can_activate_without_media_work(self):
  with tempfile.TemporaryDirectory(dir=root/'work') as temp:
   project=Path(temp);package,library=self.setup_package(project)
   ctx=stage_retry(project,'guid','retry');staged=Path(ctx['staged'])
   summary=load(staged/'summary.json');summary['refinement']=dict(state='partial');atomic(staged/'summary.json',summary)
   activate_retry(ctx);selected=load(library)['guid'];self.assertEqual(selected['edition'],'edition');self.assertEqual(selected['package'],str(package.relative_to(project)))
   self.assertEqual(selected['index_directory'],str(staged.relative_to(project)));self.assertEqual(load(package/'indexing/summary.json').get('refinement'),None)
 def test_stale_original_refuses_activation(self):
  with tempfile.TemporaryDirectory(dir=root/'work') as temp:
   project=Path(temp);package,library=self.setup_package(project);before=library.read_bytes()
   ctx=stage_retry(project,'guid','retry');summary=load(Path(ctx['staged'])/'summary.json');summary['refinement']=dict(state='completed');atomic(Path(ctx['staged'])/'summary.json',summary)
   (package/'indexing/index.json').write_text('changed elsewhere')
   with self.assertRaisesRegex(ValueError,'changed'):activate_retry(ctx)
   self.assertEqual(library.read_bytes(),before)
if __name__=='__main__':unittest.main(argv=['refinement-retry-fixtures'],verbosity=2)
PY_TEST

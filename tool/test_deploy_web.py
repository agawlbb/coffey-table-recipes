"""Check failed uploads stop deployment and public checks never receive credentials."""
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

spec = importlib.util.spec_from_file_location('deploy', Path(__file__).with_name('deploy-web.py'))
deploy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(deploy)

class DeploymentTests(unittest.TestCase):
    def test_upload_failure_stops_before_extraction(self):
        self.run_case(False)

    def test_success_verifies_public_assets_without_authentication(self):
        self.run_case(True)

    def run_case(self, success):
        with tempfile.TemporaryDirectory() as directory:
            original = Path.cwd()
            os.chdir(directory)
            try:
                root = Path('build/web')
                (root / 'assets').mkdir(parents=True)
                metadata = dict(version='0.2.0', build=3, commit='a'*40)
                (root / 'version.json').write_text(json.dumps(metadata))
                names = ('main.dart.js', 'flutter_bootstrap.js', 'assets/FontManifest.json')
                for name in names:
                    (root / name).write_bytes(name.encode())
                session = Mock(headers={})
                upload = Mock()
                upload.json.return_value = {'status': int(success)}
                extracted = Mock()
                extracted.json.return_value = {'cpanelresult': {'event': {'result': 1}, 'data': [{'result': 1}]}}
                session.post.side_effect = [upload, extracted]
                public = Mock()
                public.json.return_value = metadata
                assets = [Mock(content=name.encode()) for name in names]
                with patch.dict(os.environ, CPANEL_USER='fixture', CPANEL_API_TOKEN='fixture-secret'), patch.object(deploy.requests, 'Session', return_value=session), patch.object(deploy.requests, 'get', side_effect=[public, *assets]) as get:
                    if success:
                        deploy.deploy()
                        self.assertEqual(get.call_count, 4)
                        for call in get.call_args_list:
                            self.assertNotIn('headers', call.kwargs)
                    else:
                        with self.assertRaises(RuntimeError):
                            deploy.deploy()
                        self.assertEqual(session.post.call_count, 1)
                        get.assert_not_called()
            finally:
                os.chdir(original)

if __name__ == '__main__':
    unittest.main()

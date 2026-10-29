"""Ensure publication failures preserve the working download and older packages."""
import base64
import hashlib
import io
import json
import urllib.parse
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch
import zipfile

spec = importlib.util.spec_from_file_location('publish_android', Path(__file__).with_name('publish-android.py'))
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)


class PublicationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.directory = root / 'public'
        self.directory.mkdir()
        self.old = self.directory / 'CoffeyTableRecipes-2.2.0-build37.apk'
        self.old.write_bytes(b'previous verified release')
        (self.directory / 'latest.apk').symlink_to(self.old.name)
        self.apk = root / 'new.apk'
        with zipfile.ZipFile(self.apk, 'w') as package:
            package.writestr('AndroidManifest.xml', b'test fixture')
        self.notify = Mock()
        self.sha = hashlib.sha256(self.apk.read_bytes()).hexdigest()

    def publish(self, sha=None):
        return publisher.publish(self.apk, '2.2.1', 38, sha or self.sha, self.directory, notify=self.notify)

    def assert_previous_preserved(self):
        self.assertTrue(self.old.exists())
        self.assertEqual((self.directory / 'latest.apk').resolve(), self.old)

    def test_success_verifies_both_urls_before_removing_only_old_releases(self):
        unrelated = self.directory / 'migration-test.apk'
        unrelated.write_bytes(b'keep')
        newer = self.directory / 'CoffeyTableRecipes-2.2.2-build39.apk'
        newer.write_bytes(b'keep future package')

        def verify(url, sha):
            self.assertTrue(self.old.exists())
            self.assertEqual(hashlib.sha256((self.directory / url.rsplit('/', 1)[1]).read_bytes()).hexdigest(), sha)

        with patch.object(publisher, 'verify_download', side_effect=verify) as check:
            result = self.publish()
        self.assertEqual(check.call_count, 2)
        self.assertEqual(result['removed'], [self.old.name])
        self.assertTrue(unrelated.exists())
        self.assertTrue(newer.exists())
        self.assertEqual((self.directory / 'latest.apk').read_bytes(), self.apk.read_bytes())

    def test_checksum_failure_keeps_existing_download(self):
        with self.assertRaisesRegex(ValueError, 'Source APK checksum'):
            self.publish('0' * 64)
        self.assert_previous_preserved()

    def test_version_download_failure_keeps_existing_download(self):
        with patch.object(publisher, 'verify_download', side_effect=ValueError('unavailable')):
            with self.assertRaisesRegex(ValueError, 'unavailable'):
                self.publish()
        self.assert_previous_preserved()

    def test_latest_download_failure_restores_previous_link_and_keeps_packages(self):
        with patch.object(publisher, 'verify_download', side_effect=[None, ValueError('bad latest')]):
            with self.assertRaisesRegex(ValueError, 'bad latest'):
                self.publish()
        self.assert_previous_preserved()

    def test_refuses_to_replace_newer_release(self):
        latest = self.directory / 'latest.apk'
        latest.unlink()
        latest.symlink_to('CoffeyTableRecipes-2.2.2-build39.apk')
        with self.assertRaisesRegex(ValueError, 'newer release'):
            self.publish()
        self.assertTrue(self.old.exists())

    def test_refuses_changed_contents_under_existing_release_name(self):
        (self.directory / 'CoffeyTableRecipes-2.2.1-build38.apk').write_bytes(b'different package')
        with self.assertRaisesRegex(ValueError, 'different contents'):
            self.publish()
        self.assert_previous_preserved()


    def test_metadata_and_push_follow_download_verification_and_retry_is_quiet(self):
        def notify(version, build):
            self.assertEqual((version, build), ('2.2.1', 38))
            import json
            metadata = json.loads((self.directory / 'latest.json').read_text())
            self.assertEqual(metadata['build'], 38)
            self.assertTrue(self.old.exists())
        self.notify.side_effect = notify
        with patch.object(publisher, 'verify_download'):
            self.publish()
            self.publish()
        self.notify.assert_called_once_with('2.2.1', 38)

    def test_push_failure_keeps_packages_and_retries_without_false_success(self):
        self.notify.side_effect = RuntimeError('push unavailable')
        with patch.object(publisher, 'verify_download'):
            with self.assertRaisesRegex(RuntimeError, 'push unavailable'):
                self.publish()
            self.assertTrue(self.old.exists())
            self.assertFalse((self.directory.parent / '.android-update-sent.json').exists())
            self.notify.side_effect = None
            self.publish()
        self.assertEqual(self.notify.call_count, 2)

    def test_failed_download_does_not_advertise_or_notify(self):
        with patch.object(publisher, 'verify_download', side_effect=ValueError('offline')):
            with self.assertRaises(ValueError):
                self.publish()
        self.assertFalse((self.directory / 'latest.json').exists())
        self.notify.assert_not_called()


class SenderTests(unittest.TestCase):
    def test_scoped_oauth_and_android_only_topic_payload(self):
        with tempfile.TemporaryDirectory() as root:
            credential = Path(root) / 'service.json'
            credential.write_text(json.dumps(dict(project_id='coffey-table-recipes',
                client_email='sender@example.test', private_key='fixture-key')))
            oauth = Mock()
            oauth.__enter__ = Mock(return_value=io.BytesIO(b'{"access_token":"fixture-token"}'))
            oauth.__exit__ = Mock(return_value=False)
            fcm = Mock()
            fcm.__enter__ = Mock(return_value=Mock(status=200))
            fcm.__exit__ = Mock(return_value=False)
            with patch.object(publisher.subprocess, 'run', return_value=Mock(stdout=b'signature')), \
                 patch.object(publisher.urllib.request, 'urlopen', side_effect=[oauth, fcm]) as request:
                publisher.send_update(credential, '2.3.0', 39)
            auth_request = request.call_args_list[0].args[0]
            assertion = urllib.parse.parse_qs(auth_request.data.decode())['assertion'][0]
            encoded = assertion.split('.')[1]
            claims = json.loads(base64.urlsafe_b64decode(encoded + '=' * (-len(encoded) % 4)))
            self.assertEqual(claims['scope'], 'https://www.googleapis.com/auth/firebase.messaging')
            self.assertEqual(claims['exp'] - claims['iat'], 3600)
            push_request = request.call_args_list[1].args[0]
            message = json.loads(push_request.data)['message']
            self.assertEqual(message['topic'], 'android_releases')
            self.assertEqual(message['data'], dict(kind='android_update', version='2.3.0', build='39'))
            self.assertEqual(message['android']['priority'], 'HIGH')
            self.assertNotIn('token', message)
            self.assertNotIn('apns', message)

    def test_wrong_project_cannot_send(self):
        with tempfile.TemporaryDirectory() as root:
            credential = Path(root) / 'service.json'
            credential.write_text('{"project_id":"another-project"}')
            with patch.object(publisher.urllib.request, 'urlopen') as request:
                with self.assertRaisesRegex(ValueError, 'Wrong Firebase'):
                    publisher.send_update(credential, '2.3.0', 39)
                request.assert_not_called()


if __name__ == '__main__':
    unittest.main()

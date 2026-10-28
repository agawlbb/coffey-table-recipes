"""Ensure publication failures preserve the working download and older packages."""
import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
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
        self.sha = hashlib.sha256(self.apk.read_bytes()).hexdigest()

    def publish(self, sha=None):
        return publisher.publish(self.apk, '2.2.1', 38, sha or self.sha, self.directory)

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


if __name__ == '__main__':
    unittest.main()

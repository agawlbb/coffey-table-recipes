"""Drive publication never trashes old APKs before verifying the replacement."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch
import zipfile

spec = importlib.util.spec_from_file_location('publisher', Path(__file__).with_name('publish-android.py'))
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)


class FakeDrive:
    def __init__(self):
        self.data = {'CoffeyTableRecipes-2.2.0-build37.apk': b'old',
                     'inspection-only.apk': b'keep', 'signed-ios.ipa': b'keep'}
        self.actions = []

    def files(self):
        return [dict(Name=name, ID='file_' + str(i)) for i, name in enumerate(self.data)]

    def upload(self, apk, filename):
        self.actions.append('upload')
        self.data[filename] = apk.read_bytes()

    def sha256(self, filename):
        self.actions.append('verify')
        return hashlib.sha256(self.data[filename]).hexdigest()

    def trash(self, filename):
        self.actions.append('trash')
        del self.data[filename]


class PublicationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.apk = Path(self.temp.name) / 'release.apk'
        with zipfile.ZipFile(self.apk, 'w') as z:
            z.writestr('AndroidManifest.xml', b'fixture')
        self.sha = hashlib.sha256(self.apk.read_bytes()).hexdigest()
        self.drive = FakeDrive()
        self.old = 'CoffeyTableRecipes-2.2.0-build37.apk'
        self.name = 'CoffeyTableRecipes-2.3.0-build39.apk'

    def publish(self, sha=None):
        return publisher.publish(self.apk, '2.3.0', 39, sha or self.sha, self.drive)

    def test_success_verifies_before_trashing_only_older_releases(self):
        result = self.publish()
        self.assertEqual(self.drive.actions, ['upload', 'verify', 'trash'])
        self.assertEqual(result['removed'], [self.old])
        self.assertIn('inspection-only.apk', self.drive.data)
        self.assertIn('signed-ios.ipa', self.drive.data)
        self.assertEqual(self.drive.data[self.name], self.apk.read_bytes())
        self.assertTrue(result['url'].startswith('https://drive.google.com/file/d/'))

    def test_bad_source_checksum_never_contacts_drive(self):
        with patch.object(self.drive, 'files') as listing:
            with self.assertRaisesRegex(ValueError, 'Source APK checksum'):
                self.publish('0' * 64)
        listing.assert_not_called()

    def test_invalid_apk_never_contacts_drive(self):
        self.apk.write_bytes(b'not a zip')
        with patch.object(self.drive, 'files') as listing:
            with self.assertRaises(zipfile.BadZipFile):
                self.publish(hashlib.sha256(self.apk.read_bytes()).hexdigest())
        listing.assert_not_called()

    def test_upload_failure_preserves_old_release(self):
        with patch.object(self.drive, 'upload', side_effect=RuntimeError('offline')):
            with self.assertRaises(RuntimeError):
                self.publish()
        self.assertIn(self.old, self.drive.data)
        self.assertNotIn('trash', self.drive.actions)

    def test_download_verification_failure_preserves_old_release(self):
        with patch.object(self.drive, 'sha256', return_value='0' * 64):
            with self.assertRaisesRegex(ValueError, 'Drive APK checksum'):
                self.publish()
        self.assertIn(self.old, self.drive.data)
        self.assertNotIn('trash', self.drive.actions)

    def test_retry_reuses_same_verified_file(self):
        self.publish()
        self.drive.actions.clear()
        self.publish()
        self.assertEqual(self.drive.actions, ['verify'])

    def test_changed_existing_release_is_not_overwritten(self):
        self.drive.data[self.name] = b'changed'
        with self.assertRaisesRegex(ValueError, 'Drive APK checksum'):
            self.publish()
        self.assertEqual(self.drive.data[self.name], b'changed')
        self.assertIn(self.old, self.drive.data)
        self.assertNotIn('upload', self.drive.actions)

    def test_newer_or_same_build_conflict_refuses_publication(self):
        for name in ['CoffeyTableRecipes-2.4.0-build40.apk', 'CoffeyTableRecipes-2.2.9-build39.apk']:
            with self.subTest(name=name):
                self.drive.data[name] = b'keep'
                with self.assertRaisesRegex(ValueError, 'newer or conflicting'):
                    self.publish()
                del self.drive.data[name]
        self.assertEqual(self.drive.actions, [])

    def test_duplicate_release_names_require_review(self):
        rows = self.drive.files()
        with patch.object(self.drive, 'files', return_value=rows + rows):
            with self.assertRaisesRegex(ValueError, 'Duplicate'):
                self.publish()
        self.assertEqual(self.drive.actions, [])

    def test_cleanup_failure_retains_verified_new_release(self):
        with patch.object(self.drive, 'trash', side_effect=RuntimeError('offline')):
            with self.assertRaises(RuntimeError):
                self.publish()
        self.assertEqual(self.drive.data[self.name], self.apk.read_bytes())
        self.assertIn(self.old, self.drive.data)

    def test_missing_file_id_prevents_cleanup(self):
        original = self.drive.files
        def files():
            return [{**row, 'ID': ''} for row in original()]
        with patch.object(self.drive, 'files', side_effect=files):
            with self.assertRaisesRegex(ValueError, 'identify'):
                self.publish()
        self.assertIn(self.old, self.drive.data)


class DriveTests(unittest.TestCase):
    def test_commands_are_confined_to_folder_and_delete_uses_trash(self):
        drive = publisher.Drive('/private/rclone', '/private/rclone.conf', 'ctr-drive', 'folder_12345')
        with patch.object(publisher.subprocess, 'run', return_value=Mock(returncode=0, stdout='[]')) as run:
            drive.files()
            drive.trash('CoffeyTableRecipes-2.2.0-build37.apk')
        for call in run.call_args_list:
            command = call.args[0]
            self.assertIn('--drive-root-folder-id', command)
            self.assertIn('folder_12345', command)
            self.assertIn('--drive-use-trash=true', command)
        self.assertIn('deletefile', run.call_args.args[0])
        self.assertNotIn('sync', run.call_args.args[0])

    def test_invalid_remote_or_folder_is_rejected(self):
        for remote, folder in [('drive:elsewhere', 'folder_12345'), ('ctr-drive', '../other')]:
            with self.assertRaises(ValueError):
                publisher.Drive('rclone', 'private.conf', remote, folder)

    def test_failure_does_not_print_private_process_output(self):
        drive = publisher.Drive('rclone', 'private.conf', 'ctr-drive', 'folder_12345')
        with patch.object(publisher.subprocess, 'run', return_value=Mock(returncode=1, stdout='', stderr='private-token')):
            with self.assertRaisesRegex(RuntimeError, 'operation failed') as error:
                drive.files()
        self.assertNotIn('private-token', str(error.exception))


if __name__ == '__main__':
    unittest.main()

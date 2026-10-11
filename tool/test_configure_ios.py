import json
import plistlib
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

class IOSShareConfigurationTests(unittest.TestCase):
    def test_google_callback_configuration_preserves_share_callback(self):
        with tempfile.TemporaryDirectory() as directory:
            workspace = Path(directory)
            plist = workspace / 'ios/Runner/Info.plist'
            plist.parent.mkdir(parents=True)
            plist.write_bytes((ROOT / 'ios/Runner/Info.plist').read_bytes())
            config = workspace / 'firebase.json'
            config.write_text(json.dumps({'FIREBASE_IOS_APP_ID': 'fixture', 'FIREBASE_IOS_API_KEY': 'fixture', 'GOOGLE_IOS_CLIENT_ID': 'fixture.apps.googleusercontent.com'}))
            for _ in range(2):
                subprocess.run([sys.executable, str(ROOT / 'tool/configure-ios.py'), str(config)], cwd=workspace, check=True)
            info = plistlib.loads(plist.read_bytes())
            schemes = [value for entry in info['CFBundleURLTypes'] for value in entry['CFBundleURLSchemes']]
            self.assertIn('ShareMedia-$(PRODUCT_BUNDLE_IDENTIFIER)', schemes)
            self.assertIn('com.googleusercontent.apps.fixture', schemes)
            self.assertEqual(len(schemes), 2)

    def test_extension_and_app_use_matching_groups_and_file_activation(self):
        runner = plistlib.loads((ROOT / 'ios/Runner/Info.plist').read_bytes())
        extension = plistlib.loads((ROOT / 'ios/ShareExtension/Info.plist').read_bytes())
        for name in ['Runner/Runner.entitlements', 'ShareExtension/ShareExtension.entitlements']:
            entitlements = plistlib.loads((ROOT / 'ios' / name).read_bytes())
            self.assertEqual(entitlements['com.apple.security.application-groups'], [runner['AppGroupId']])
        self.assertEqual(extension['AppGroupId'], runner['AppGroupId'])
        rule = extension['NSExtension']['NSExtensionAttributes']['NSExtensionActivationRule']
        self.assertGreater(rule['NSExtensionActivationSupportsFileWithMaxCount'], 0)
        self.assertGreater(rule['NSExtensionActivationSupportsImageWithMaxCount'], 0)
        self.assertTrue(rule['NSExtensionActivationSupportsText'])
        self.assertEqual(extension['NSExtension']['NSExtensionPrincipalClass'], '$(PRODUCT_MODULE_NAME).ShareViewController')

if __name__ == '__main__':
    unittest.main()

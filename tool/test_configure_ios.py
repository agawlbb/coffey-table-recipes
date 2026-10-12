import json
import plistlib
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

class IOSShareConfigurationTests(unittest.TestCase):
    def test_file_opening_uses_copy_mode_and_supported_recipe_documents(self):
        runner = plistlib.loads((ROOT / 'ios/Runner/Info.plist').read_bytes())
        self.assertFalse(runner['LSSupportsOpeningDocumentsInPlace'])
        documents = runner['CFBundleDocumentTypes']
        self.assertEqual(len(documents), 1)
        self.assertEqual(documents[0]['CFBundleTypeRole'], 'Viewer')
        self.assertEqual(set(documents[0]['LSItemContentTypes']), {'com.adobe.pdf', 'public.image', 'public.plain-text'})

    def test_extension_uses_visible_persistent_handoff_without_plugin_launch(self):
        source = (ROOT / 'ios/ShareExtension/ShareViewController.swift').read_text()
        project = (ROOT / 'ios/Runner.xcodeproj/project.pbxproj').read_text()
        self.assertNotIn('ShareHandlerIosViewController', source)
        self.assertNotIn('UIApplication', source)
        self.assertNotIn('better-share-handler-models', project)
        self.assertIn('Ready to import.', source)
        self.assertIn('options: .atomic', source)

    def test_extension_is_embedded_before_flutter_thinning(self):
        project = (ROOT / 'ios/Runner.xcodeproj/project.pbxproj').read_text()
        runner = project.split('97C146ED1CF9000F007C117D /* Runner */ = {', 1)[1]
        phases = runner.split('buildPhases = (', 1)[1].split(');', 1)[0]
        self.assertLess(phases.index('7FEAB63A8052A2CE3F548F05'), phases.index('3B06AD1E1E4923F5004D2608'))

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

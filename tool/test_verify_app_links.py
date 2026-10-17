import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("verify_app_links", Path(__file__).with_name("verify-app-links.py"))
links = importlib.util.module_from_spec(spec)
spec.loader.exec_module(links)


class AppLinksTests(unittest.TestCase):
    def setUp(self):
        self.data = [{"relation": ["delegate_permission/common.handle_all_urls"], "target": {
            "namespace": "android_app", "package_name": links.PACKAGE,
            "sha256_cert_fingerprints": [links.FINGERPRINT]}}]

    def test_matching_certificate_preserves_other_apps(self):
        links.validate([{"target": {"package_name": "another.app"}}, *self.data], links.FINGERPRINT.replace(":", "").lower())

    def test_wrong_certificate_app_namespace_or_relation_fails(self):
        for key, value in [("package_name", "another.app"), ("namespace", "web"), ("sha256_cert_fingerprints", ["00" * 32])]:
            with self.subTest(key=key):
                data = copy.deepcopy(self.data)
                data[0]["target"][key] = value
                with self.assertRaises(ValueError):
                    links.validate(data)
        self.data[0]["relation"] = []
        with self.assertRaises(ValueError):
            links.validate(self.data)

    def test_html_or_missing_association_fails(self):
        for data in [{}, [], "<html>Not found</html>"]:
            with self.assertRaises(ValueError):
                links.validate(data)


if __name__ == "__main__":
    unittest.main()

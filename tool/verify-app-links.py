"""Read-only release check; never builds, deploys, or changes device settings."""
import argparse
import json
import re
import urllib.request

URL = "https://coffeybean.com/.well-known/assetlinks.json"
PACKAGE = "com.coffeytable.coffey_table_recipes"
# Public certificate verified from the delivered 1.6.0 Android APK.
FINGERPRINT = "F8:DE:93:3F:14:B9:BB:4B:31:91:A9:4A:ED:C8:63:79:72:C5:AB:22:45:65:F6:AB:D7:80:8F:80:38:D1:20:97"


def normalize(value):
    value = value.replace(":", "").upper()
    if not re.fullmatch(r"[0-9A-F]{64}", value):
        raise ValueError("Expected a SHA-256 signing-certificate fingerprint")
    return value


def validate(data, fingerprint=FINGERPRINT):
    expected = normalize(fingerprint)
    if not isinstance(data, list):
        raise ValueError("assetlinks.json must be a JSON array")
    for entry in data:
        if not isinstance(entry, dict):
            continue
        target = entry.get("target", {})
        if not isinstance(target, dict):
            continue
        if ("delegate_permission/common.handle_all_urls" in entry.get("relation", [])
                and target.get("namespace") == "android_app"
                and target.get("package_name") == PACKAGE
                and any(normalize(value) == expected for value in target.get("sha256_cert_fingerprints", []))):
            return
    raise ValueError("No association matches the released Android app and signing certificate")


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def verify(fingerprint=FINGERPRINT):
    opener = urllib.request.build_opener(NoRedirect)
    with opener.open(URL, timeout=30) as response:
        if response.status != 200 or response.headers.get_content_type() != "application/json":
            raise ValueError("Require HTTP 200 and application/json, without redirects")
        validate(json.load(response), fingerprint)
    print("Verified Android app links for the release signing certificate")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fingerprint", default=FINGERPRINT)
    verify(parser.parse_args().fingerprint)

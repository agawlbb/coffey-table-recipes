"""Verify a signed App Store Connect IPA on macOS without publishing it."""
import hashlib
from datetime import datetime
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile
import zipfile

ipa = Path(sys.argv[1])
team = os.environ["IOS_TEAM_ID"]
build = os.environ["IOS_BUILD_NUMBER"]
version = re.search(r"^version:\s*([^+\s]+)", Path("pubspec.yaml").read_text(), re.M)[1]
expected = {
    "Runner.app/PlugIns/TimerWidget.appex": "com.coffeytable.coffeyTableRecipes.TimerWidget",
    "Runner.app": "com.coffeytable.coffeyTableRecipes",
    "Runner.app/PlugIns/ShareExtension.appex": "com.coffeytable.coffeyTableRecipes.ShareExtension",
}
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    with zipfile.ZipFile(ipa) as archive:
        for member in archive.infolist():
            destination = (root / member.filename).resolve()
            if not destination.is_relative_to(root.resolve()):
                raise SystemExit("Unsafe IPA member path")
    # Preserve Apple's sealed symlinks and executable permissions.
    subprocess.run(["ditto", "-x", "-k", str(ipa.resolve()), str(root)], check=True)
    checked = []
    for relative, bundle in expected.items():
        app = root / "Payload" / relative
        subprocess.run(["codesign", "--verify", "--strict", str(app)], check=True)
        info = plistlib.loads((app / "Info.plist").read_bytes())
        assert info["CFBundleIdentifier"] == bundle, "Unexpected bundle identifier"
        assert info["CFBundleVersion"] == build, "Unexpected build number"
        assert info["CFBundleShortVersionString"] == version, "Unexpected version"
        assert info.get("ITSAppUsesNonExemptEncryption") is False, "Missing encryption declaration"
        profile = plistlib.loads(subprocess.check_output([
            "security", "cms", "-D", "-i", str(app / "embedded.mobileprovision")
        ]))
        entitlements = profile["Entitlements"]
        signed_entitlements = plistlib.loads(subprocess.check_output([
            "codesign", "-d", "--entitlements", ":-", str(app)
        ], stderr=subprocess.DEVNULL))
        assert profile["TeamIdentifier"] == [team], "Unexpected profile team"
        assert profile["ExpirationDate"] > datetime.utcnow(), "Expired provisioning profile"
        assert entitlements["application-identifier"] == team + "." + bundle, "Wrong target profile"
        assert not entitlements.get("get-task-allow", False), "Development profile in distribution IPA"
        assert "ProvisionedDevices" not in profile, "Device-only profile in App Store IPA"
        assert not profile.get("ProvisionsAllDevices", False), "Enterprise profile in App Store IPA"
        assert signed_entitlements["application-identifier"] == team + "." + bundle, "Wrong signed identifier"
        assert signed_entitlements["com.apple.developer.team-identifier"] == team, "Wrong signing team"
        assert not signed_entitlements.get("get-task-allow", False), "Development signing entitlements"
        if not relative.endswith("TimerWidget.appex"):
            assert "group.com.coffeytable.coffeyTableRecipes" in signed_entitlements.get(
                "com.apple.security.application-groups", []
            ), "App Group missing from signed entitlements"
            assert "group.com.coffeytable.coffeyTableRecipes" in entitlements.get(
                "com.apple.security.application-groups", []
            ), "App Group missing from profile"
        checked.append({"bundle": bundle, "version": version, "build": build,
                        "signature": "verified", "profile": "App Store Connect"})
    report = {"ipa": ipa.name, "sha256": hashlib.sha256(ipa.read_bytes()).hexdigest(),
              "source_commit": os.environ["GITHUB_SHA"], "export_method": "app-store-connect",
              "targets": checked}
    (ipa.parent / "verification.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))

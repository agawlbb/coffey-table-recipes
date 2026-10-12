"""Apply ignored Firebase configuration to Google callbacks and the share importer."""
import json
import plistlib
import sys
from pathlib import Path

config = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8-sig"))
required = ("FIREBASE_IOS_APP_ID", "FIREBASE_IOS_API_KEY", "GOOGLE_IOS_CLIENT_ID")
if any(not config.get(key) for key in required):
    raise SystemExit("iOS Firebase app ID, API key and Google client ID are required")
client_id = config["GOOGLE_IOS_CLIENT_ID"]
scheme = ".".join(reversed(client_id.split(".")))
path = Path("ios/Runner/Info.plist")
with path.open("rb") as source:
    info = plistlib.load(source)
callbacks = [entry for entry in info.get("CFBundleURLTypes", [])
             if any(item.startswith("ShareMedia-") for item in entry.get("CFBundleURLSchemes", []))]
info["CFBundleURLTypes"] = callbacks + [{"CFBundleTypeRole": "Editor", "CFBundleURLSchemes": [scheme]}]
with path.open("wb") as target:
    plistlib.dump(info, target, sort_keys=False)

# Client configuration, generated only for builds and deliberately excluded from Git.
# A separate override supports API keys restricted to the extension's bundle ID.
share_config = Path("ios/ShareExtension/ShareUI/FirebaseConfig.json")
share_config.parent.mkdir(parents=True, exist_ok=True)
share_config.write_text(json.dumps({
    "apiKey": config.get("FIREBASE_SHARE_API_KEY") or config["FIREBASE_IOS_API_KEY"],
}), encoding="utf-8")

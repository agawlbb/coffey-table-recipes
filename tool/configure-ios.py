"""Apply ignored Firebase client configuration to the iOS Google callback."""
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
info["CFBundleURLTypes"] = [{"CFBundleTypeRole": "Editor", "CFBundleURLSchemes": [scheme]}]
with path.open("wb") as target:
    plistlib.dump(info, target, sort_keys=False)

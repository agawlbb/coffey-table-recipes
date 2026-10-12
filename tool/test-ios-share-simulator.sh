#!/bin/bash
set -euo pipefail

mkdir -p build/ios-share-probe
device=$(xcrun simctl list devices available --json | python3 -c '
import json,sys,os
devices=json.load(sys.stdin)["devices"]
for runtime in sorted(devices, reverse=True):
    major=os.environ.get("IOS_RUNTIME_MAJOR", "")
    if ".iOS-" in runtime and (not major or (".iOS-"+major+"-") in runtime):
        for device in devices[runtime]:
            if device["name"].startswith("iPhone") and device.get("isAvailable"):
                print("Selected "+device["name"]+" on "+runtime, file=sys.stderr)
                print(device["udid"])
                sys.exit(0)
sys.exit("No installed iPhone simulator is available")
')
echo "Using simulator $device"
xcrun simctl boot "$device" || true
xcrun simctl bootstatus "$device" -b
# Give simulator processes the same App Group entitlement as the paid build.
# This is local ad-hoc signing, not Apple device provisioning.
codesign --force --sign - --entitlements ios/ShareExtension/ShareExtension.entitlements \
  build/ios/iphonesimulator/Runner.app/PlugIns/ShareExtension.appex
codesign --force --sign - --entitlements ios/Runner/Runner.entitlements \
  build/ios/iphonesimulator/Runner.app
xcrun simctl install "$device" build/ios/iphonesimulator/Runner.app

if ! ruby -rxcodeproj -e 'puts Xcodeproj::VERSION'; then
  gem install xcodeproj --user-install --no-document
fi
ruby tool/ios-share-probe/generate-project.rb

# Keep simulator screenshots, test results and launch logs even if a test fails.
diagnostics() {
  xcrun simctl io "$device" screenshot build/ios-share-probe/final-screen.png || true
  xcrun simctl spawn "$device" log show --last 10m --style compact \
    --predicate 'process == "ShareProbe" OR process == "ShareExtension" OR eventMessage CONTAINS "com.coffeytable.coffeyTableRecipes.ShareExtension"' \
    > build/ios-share-probe/extension-launch.log 2>&1 || true
  python3 - <<'PY'
from pathlib import Path
import shutil
destination=Path('build/ios-share-probe/crashes')
destination.mkdir(parents=True,exist_ok=True)
for prefix in ['ShareProbe', 'ShareExtension']:
    for report in (Path.home()/'Library/Logs/DiagnosticReports').glob(prefix+'*.ips'):
        shutil.copy2(report,destination/report.name)
PY
  if [[ -d build/ios-share-probe/results.xcresult ]]; then
    xcrun xcresulttool export attachments --path build/ios-share-probe/results.xcresult \
      --output-path build/ios-share-probe/screenshots || true
  fi
}
trap diagnostics EXIT

xcodebuild test -project build/ios-share-probe/ShareProbe.xcodeproj \
  -scheme ShareProbe -destination "platform=iOS Simulator,id=$device" \
  -derivedDataPath build/ios-share-probe/DerivedData \
  -resultBundlePath build/ios-share-probe/results.xcresult \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO

group=$(xcrun simctl get_app_container "$device" com.coffeytable.coffeyTableRecipes group.com.coffeytable.coffeyTableRecipes)
python3 - "$group" <<'PY'
import json, sys
from pathlib import Path
root = Path(sys.argv[1])
payloads = [json.loads(p.read_text()) for p in root.glob('RecipeShare-*.json')]
assert any(p['content'] for p in payloads), 'Text share was not persisted'
files = [Path(a['path']) for p in payloads for a in p['attachments']]
assert any(p.suffix.lower() == '.pdf' and p.read_bytes().startswith(b'%PDF') for p in files), 'PDF bytes were not persisted'
assert all(p.is_file() for p in files), 'Manifest points at a removed attachment'
print('App Group PDF and text persistence verified')
PY

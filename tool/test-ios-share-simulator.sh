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

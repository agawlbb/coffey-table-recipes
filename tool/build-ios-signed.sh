#!/bin/bash
# Run on a Mac with Xcode, Flutter, and the paid Apple team added to Xcode.
set -euo pipefail
: "${IOS_TEAM_ID:?Set IOS_TEAM_ID to your paid Apple developer team ID}"
: "${IOS_FIREBASE_CONFIG:?Set IOS_FIREBASE_CONFIG to the ignored Firebase JSON file}"
[[ "$IOS_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || { echo 'Invalid Apple team ID'; exit 1; }
[[ -f "$IOS_FIREBASE_CONFIG" ]] || { echo 'Firebase configuration file not found'; exit 1; }
export IOS_EXPORT_METHOD="${IOS_EXPORT_METHOD:-debugging}"
case "$IOS_EXPORT_METHOD" in debugging|release-testing|app-store-connect) ;; *) echo 'Unsupported export method'; exit 1 ;; esac
export IOS_TEAM_ID
python3 tool/configure-ios.py "$IOS_FIREBASE_CONFIG"
flutter pub get
flutter build ios --release --no-codesign --dart-define-from-file="$IOS_FIREBASE_CONFIG"
mkdir -p build/ios/signing
python3 - <<'PY'
import os, plistlib
from pathlib import Path
Path('build/ios/signing/ExportOptions.plist').write_bytes(plistlib.dumps({
    'method': os.environ['IOS_EXPORT_METHOD'],
    'teamID': os.environ['IOS_TEAM_ID'],
    'signingStyle': 'automatic',
    'manageAppVersionAndBuildNumber': False,
}))
PY
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Release \
  -archivePath build/ios/archive/Runner.xcarchive archive \
  DEVELOPMENT_TEAM="$IOS_TEAM_ID" CODE_SIGN_STYLE=Automatic CODE_SIGNING_ALLOWED=YES \
  -allowProvisioningUpdates
app=build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app
codesign --verify --strict "$app/PlugIns/ShareExtension.appex"
codesign --verify --strict "$app"
xcodebuild -exportArchive -archivePath build/ios/archive/Runner.xcarchive \
  -exportPath build/ios/signed -exportOptionsPlist build/ios/signing/ExportOptions.plist \
  -allowProvisioningUpdates
echo 'Signed IPA exported to build/ios/signed. No upload was performed.'

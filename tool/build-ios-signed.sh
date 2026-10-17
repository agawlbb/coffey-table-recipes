#!/bin/bash
# Run on a Mac with Xcode, Flutter, and the paid Apple team added to Xcode.
set -euo pipefail
heartbeat_pid=''
cleanup_heartbeat() {
  if [[ -n "$heartbeat_pid" ]]; then
    kill "$heartbeat_pid" 2>/dev/null || true
    wait "$heartbeat_pid" 2>/dev/null || true
  fi
}
trap cleanup_heartbeat EXIT
# Report executable names only; command arguments can contain signing credentials.
(
  while true; do
    sleep 60
    echo "::group::Signing build heartbeat $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    ps -axo pid,pcpu,pmem,comm | sort -k2 -nr | head -12 || true
    vm_stat || true
    echo '::endgroup::'
  done
) &
heartbeat_pid=$!
version=$(xcodebuild -version)
[[ "$version" =~ Xcode[[:space:]]([0-9]+) ]] && (( ${BASH_REMATCH[1]} >= 27 )) || {
  echo 'Use Xcode 27 or newer for the validated iOS 27 signing path'; exit 1;
}
: "${IOS_TEAM_ID:?Set IOS_TEAM_ID to your paid Apple developer team ID}"
: "${IOS_FIREBASE_CONFIG:?Set IOS_FIREBASE_CONFIG to the ignored Firebase JSON file}"
[[ "$IOS_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || { echo 'Invalid Apple team ID'; exit 1; }
[[ -f "$IOS_FIREBASE_CONFIG" ]] || { echo 'Firebase configuration file not found'; exit 1; }
# Standard Apple Silicon runners have limited memory. Bound native concurrency
# while keeping the compiler and SDK identical to the previously validated path.
IOS_XCODE_JOBS="${IOS_XCODE_JOBS:-2}"
[[ "$IOS_XCODE_JOBS" =~ ^[1-9][0-9]?$ ]] || { echo 'Invalid Xcode job count'; exit 1; }
export IOS_EXPORT_METHOD="${IOS_EXPORT_METHOD:-debugging}"
case "$IOS_EXPORT_METHOD" in debugging|release-testing|app-store-connect) ;; *) echo 'Unsupported export method'; exit 1 ;; esac
export IOS_TEAM_ID
export IOS_UPLOAD="${IOS_UPLOAD:-false}"
case "$IOS_UPLOAD" in true|false) ;; *) echo 'IOS_UPLOAD must be true or false'; exit 1 ;; esac
[[ "$IOS_UPLOAD" != true || "$IOS_EXPORT_METHOD" == app-store-connect ]] || {
  echo 'Uploading requires app-store-connect export'; exit 1;
}
auth=()
if [[ -n "${ASC_KEY_PATH:-}${ASC_KEY_ID:-}${ASC_ISSUER_ID:-}" ]]; then
  : "${ASC_KEY_PATH:?Set ASC_KEY_PATH}" "${ASC_KEY_ID:?Set ASC_KEY_ID}" "${ASC_ISSUER_ID:?Set ASC_ISSUER_ID}"
  [[ -f "$ASC_KEY_PATH" ]] || { echo 'App Store Connect key file not found'; exit 1; }
  auth=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
fi
build_args=()
if [[ -n "${IOS_BUILD_NUMBER:-}" ]]; then
  [[ "$IOS_BUILD_NUMBER" =~ ^[1-9][0-9]{0,8}$ ]] || { echo 'Invalid build number'; exit 1; }
  build_args+=("--build-number=$IOS_BUILD_NUMBER")
fi
python3 tool/configure-ios.py "$IOS_FIREBASE_CONFIG"
echo '::notice::Stage: prepare unsigned Flutter app'
flutter pub get
flutter build ios --release --no-codesign --dart-define-from-file="$IOS_FIREBASE_CONFIG" "${build_args[@]}"
mkdir -p build/ios/signing
python3 - <<'PY'
import os, plistlib
from pathlib import Path
Path('build/ios/signing/ExportOptions.plist').write_bytes(plistlib.dumps({
    'method': os.environ['IOS_EXPORT_METHOD'],
    'teamID': os.environ['IOS_TEAM_ID'],
    'signingStyle': 'automatic',
    'manageAppVersionAndBuildNumber': False,
    'destination': 'upload' if os.environ['IOS_UPLOAD'] == 'true' else 'export',
}))
PY
echo '::notice::Stage: Apple archive and automatic provisioning'
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Release \
  -jobs "$IOS_XCODE_JOBS" \
  -destination 'generic/platform=iOS' \
  -archivePath build/ios/archive/Runner.xcarchive archive \
  DEVELOPMENT_TEAM="$IOS_TEAM_ID" CODE_SIGN_STYLE=Automatic CODE_SIGNING_ALLOWED=YES \
  -allowProvisioningUpdates "${auth[@]}"
app=build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app
codesign --verify --strict "$app/PlugIns/ShareExtension.appex"
codesign --verify --strict "$app/PlugIns/TimerWidget.appex"
codesign --verify --strict "$app"
echo '::notice::Stage: Apple export and optional TestFlight upload'
python3 - <<'PY'
import plistlib
from pathlib import Path
app = Path('build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app')
for bundle in [app, *sorted((app / 'PlugIns').glob('*.appex'))]:
    info = plistlib.loads((bundle / 'Info.plist').read_bytes())
    if not info.get('CFBundleDisplayName', '').strip():
        raise SystemExit(f'Missing App Store display name: {bundle.name}')
print('App Store display names verified for app and extensions.')
PY
xcodebuild -exportArchive -archivePath build/ios/archive/Runner.xcarchive \
  -exportPath build/ios/signed -exportOptionsPlist build/ios/signing/ExportOptions.plist \
  -allowProvisioningUpdates "${auth[@]}"
if [[ "$IOS_UPLOAD" == true ]]; then
  echo 'Upload submitted to App Store Connect. Check processing and TestFlight status there.'
else
  echo 'Signed IPA exported to build/ios/signed. No upload was performed.'
fi

# Workflow security maintenance

## Native HTTPS SDK advisory (October 24, 2026)

GHSA-frr6-h895-5pxp affects native `dart:io` HTTPS certificate verification
on Android and Windows, and Linux with an unpatched trust store. Compromised
eMudhra intermediate certificates could permit interception by an attacker on
the network path. Web, iOS and macOS are outside this advisory's affected
platforms. CTR's RecipeApi uses package:http's default native client against
the hosted HTTPS API, so the Android path is relevant. No interception has
been observed or established by this review.

Require Dart >=3.13.7,<4.0.0 and Flutter >=3.47.8 in pubspec.yaml and the
lockfile SDK requirements. All four CI Flutter clone sites now pin 3.47.8
(web, iOS device/demo, iOS simulator and signed TestFlight). This is a stable
hotfix within the existing Flutter 3.47/Dart 3.13 series, not a dependency or
native-platform migration. Locked package versions, Firebase pins, app version,
release tags, signing configuration and backend source are unchanged.

The laptop SDK is shared at
`C:\Users\mailb\flutter_windows_3.24.1-stable\flutter`; its existing
bin/cache/flutter.version.json reports Flutter 3.47.6 and Dart 3.13.5 despite
the older folder name. It was deliberately left untouched pending coordination
with other SDK users. The new constraints reject that old SDK when dependency
resolution is next run; do not bypass them with --no-pub on stale tooling.
Upgrade the coordinated SDK before any future development/build commands.

Validation for this change is static only: review workflow event definitions,
parse the modified YAML/lockfile, check matching minimum SDK requirements and
all four CI pins, confirm locked packages unchanged, and review the diff.
The lockfile's SDK metadata was aligned without dependency resolution. No
Flutter/Dart command, app test, compilation, app build, install, workflow
dispatch, release or deployment was performed. All seven app workflows accept
only workflow_dispatch; a source push cannot trigger their build jobs.

Installed APKs, including 2.1.1/build 32, were not inspected or replaced and
must not be described as remediated. A separately authorized rebuild with the
patched SDK, validation and distribution is still required for native affected
platforms. Existing SDK/test/build evidence below is historical and does not
verify compatibility of this hotfix. Firebase remains unchanged under the
owner's decision to wait for an official compatible update.

Primary source:
https://github.com/dart-lang/sdk/security/advisories/GHSA-frr6-h895-5pxp

## Earlier workflow maintenance

Reviewed October 13, 2026. All GitHub Actions in the web and iOS workflows are
pinned to exact commits resolved from their existing major-version tags:

- actions/checkout v4: `11d5960a326750d5838078e36cf38b85af677262`
- actions/upload-artifact v4: `ea165f8d65b6e75b540449e92b4886f43607fa02`

Review upstream changes and update these hashes deliberately. Version comments
are documentation; they do not control which code executes.

The next web/iOS builds use Flutter 3.47.7. Its hotfix corrects iOS accessibility
frames for OverlayPortal and VoiceOver focus for ReorderableListView. These
widgets are not directly used in this app's source, but framework widgets may
use them internally. Source:
https://github.com/flutter/flutter/blob/3.47.7/CHANGELOG.md

No app release, hosted app deployment, or macOS build was triggered for this
maintenance. Before the next iOS release, obtain the owner's explicit approval
for each paid macOS workflow run, run the release checks, and verify VoiceOver
focus/targeting on menus and recipe controls. Real iOS validation remains pending.

Validation: all seven offline iOS configuration/web deployment tests passed.
All four workflow files across both repositories parsed successfully, and all
nine action references were verified to use full commit hashes. Application
source code was unchanged; no local SDK upgrade was performed.

## Android Gradle security update (October 14, 2026)

Updated the Android wrapper from Gradle 9.3.1 to 9.8.1, which fixes the three
high-severity build-process advisories published October 7. Added the official
SHA-256 checksum for the complete distribution so the wrapper verifies its
contents before use.

Compatibility validation: `flutter build apk --debug
--dart-define-from-file=config/firebase.local.json` passed with local Flutter
3.47.6 / Dart 3.13.5, AGP 9.1.0 and the existing Kotlin 2.4.0 configuration.
The debug APK is an ignored local validation artifact. No app release, deployment,
Git push or paid macOS workflow was triggered.

Kotlin's fully tested version range for KGP 2.4.0 ends at Gradle 9.5.0; its
documentation permits newer Gradle versions with possible warnings or feature
limitations. This project passed the actual Android build on 9.8.1. Flutter
reported a future built-in Kotlin migration warning for firebase_auth and
firebase_core; review compatible plugin releases before a future Flutter upgrade.
SDK XML and Java native-access warnings also remain non-fatal.

Sources:
- https://docs.gradle.org/9.8.1/release-notes.html
- https://kotlinlang.org/docs/gradle-configure-project.html
- https://developer.android.com/build/releases/about-agp

## Kotlin/KAPT and Firebase Auth review (October 23, 2026)

### Android build tooling

Updated the external Kotlin Gradle plugin from 2.4.0 to 2.4.21 to include
the fix for GHSA-r937-wjx7-w2jp / CVE-2026-53914. The upstream fix restricts
deserialization of KAPT incremental-cache metadata. Before the update, a Gradle
projectsEvaluated inspection confirmed Kotlin 2.4.0 in the actual app/plugin
projects and no KAPT plugin, task or configuration in any inspected project.
Static inspection also found no KAPT use in the repository or the resolved
plugins' Android Gradle scripts. The affected version was present, but use of
the vulnerable cache path was not found; this is not evidence of exploitation
or a runtime vulnerability in the installed Android app.

Keep AGP 9.1.0, Java/Kotlin bytecode target 17 and the security-updated Gradle
9.8.1 wrapper. KGP 2.4.21's fully tested range includes AGP 9.1.0 but ends at
Gradle 9.7.0. Kotlin permits newer Gradle versions with possible limitations,
so the existing newer wrapper requires actual build validation rather than a
downgrade that would undo the earlier Gradle security update.

Validation: the authorized local `flutter build apk --debug
--dart-define-from-file=config/firebase.local.json` passed with Flutter 3.47.6,
Dart 3.13.5, AGP 9.1.0, Gradle 9.8.1 and Kotlin 2.4.21. Existing built-in
Kotlin migration, SDK XML, Java native-access and deprecated-API warnings
remain non-fatal. The debug APK and local inspection logs are ignored
validation artifacts; no release, upload or production deployment occurred.
The same Gradle inspection after the build confirmed resolved Kotlin 2.4.21
throughout the app/plugin projects and no KAPT plugins, tasks or configurations.

### Firebase Apple Auth: compatibility blocker

The locked firebase_core 4.15.0, firebase_auth 6.7.0 and firebase_messaging
16.7.0 Swift packages pin Firebase Apple SDK 12.19.0. The conditional legacy
duplicate-keychain-entry logging path predates the Auth logging-safety fix
in 13.1.0 (PR 16892). No actual keychain leakage has been observed. The
12.19.3 patch updates Firestore's certificate trust store and does not include
this Auth fix; CTR does not use Firestore.

Official packages released today (firebase_core 5.1.0, firebase_auth 7.0.1 and
firebase_messaging 17.0.1) all pin Apple SDK 13.1.1. CTR already uses Swift
Package Manager, but the existing Google Sign-In dependency prevents a direct
upgrade: locked google_sign_in_ios 6.3.6 and latest 6.3.8 both require native
GoogleSignIn >=9.0.0,<10.0.0. All published native 9.x manifests (9.0.0,
9.1.0 and 9.2.0) require GTMSessionFetcher >=3.3.0,<4.0.0, while Firebase
13 requires >=4.0.0. Native GoogleSignIn 10.1.0 allows the newer fetcher but
is outside the Flutter plugin's declared range.

Firebase dependencies remain unchanged. A fix needs either an official
compatible Google Sign-In Flutter release or a separately reviewed native
compatibility change/backport, including macOS/iOS dependency resolution and
authentication validation. Do not force the major SDK version into the
existing plugins or describe 12.19.3 as the Auth remediation. Moving to the
new FlutterFire major versions also raises Android minSdk to 24 and updates
the Firebase Android BoM to 35.x; assess those changes as part of that work.

Sources:
- https://github.com/advisories/GHSA-r937-wjx7-w2jp
- https://github.com/JetBrains/kotlin/commit/bf51df6
- https://kotlinlang.org/docs/gradle-configure-project.html
- https://github.com/firebase/firebase-ios-sdk/pull/16892
- https://firebase.google.com/support/release-notes/ios
- https://pub.dev/packages/firebase_core/versions/5.1.0
- https://pub.dev/packages/firebase_auth/versions/7.0.1
- https://pub.dev/packages/firebase_messaging/versions/17.0.1
- https://pub.dev/packages/google_sign_in_ios/versions/6.3.8
- https://github.com/google/GoogleSignIn-iOS/blob/9.2.0/Package.swift
- https://github.com/google/GoogleSignIn-iOS/blob/10.1.0/Package.swift

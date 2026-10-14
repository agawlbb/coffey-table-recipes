# Workflow security maintenance

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

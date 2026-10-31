# Android timer-sharing startup — 2026-10-31

The user reported `Timer sharing could not start. Reopen the app to try again.`
in build 44, including after a full restart. This message comes from
`TimerSync.start()` before backend requests; its first awaited operations read
and save the existing `timer_installation` preference.

Build 44 locks `shared_preferences_android` 2.5.0. Its signed APK is missing all
six Kotlin class names needed by that plugin's JNI bindings. This matches the
[upstream release-build failure](https://github.com/flutter/flutter/issues/194649),
whose R8 fix was included in
[2.5.2](https://github.com/flutter/packages/blob/main/packages/shared_preferences/shared_preferences_android/CHANGELOG.md).
This is artifact/source evidence; the phone's exception log was not collected.

Targeted dependency resolution updates only `shared_preferences_android` to
2.5.4; every other Dart package remains locked. Its consumer R8 rules retain the
six classes and are wired into `consumerProguardFiles`. Existing preference
keys, native storage, account state, timers and outboxes are retained. No app UI
or backend changes are needed.

The existing Android verification step now inspects the actual signed APK's DEX
classes and rejects artifacts missing these JNI names. It also records
`android_preferences_jni_verified` in the delivery report. Workflow triggers
remain manual. The test build counter prepares build 45 to upgrade build 44.

Verified before publication:

- `flutter pub upgrade shared_preferences_android`: one dependency changed.
- `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub`: all 559 tests passed once for the dependency change.
- Both embedded workflow Python blocks compile. The exact new APK guard rejects
  the existing build-44 artifact for the missing JNI classes, reproducing the
  release-specific gap that mocked preference tests cannot catch.
- `git diff --check` passed. Corrected signed-APK verification and delivery are
  recorded after the requested feature test build completes. No main merge.

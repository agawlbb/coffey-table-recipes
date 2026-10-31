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

## Corrected test APK delivery

[Android build 41229755998](https://github.com/agawlbb/coffey-table-recipes/actions/runs/41229755998)
passed from immutable feature source `aa0dc5b351646acd7cc65a52138f9401203e0265`.
Test version is `2.4.0-account-test`, build **45**.

- APK: `CoffeyTableRecipes-2.4.0-account-test-build45.apk`.
- SHA-256: `0f5956319110b4e3f0b67512705e918553841543782f613386a7aafa06b8abf8`.
- The CI guard and independent local `dexdump` check both verified all six JNI
  class names in the actual signed APK. Original signing certificate,
  package/version, non-debuggable status and hosted Android association verified.
- [Verified Drive APK](https://drive.google.com/file/d/1hzHNPCh9quRgnCqHjRc9ps1NNELFKb-Q/view).
  Uploaded to the existing pinned recipe app folder, downloaded and SHA-256
  checked. FCM accepted the informational Android update notification. Only the
  exact known superseded build-44 test APK was moved to Drive trash after this
  verification; unrelated files and stable releases were preserved.

Install over build 44 without clearing app data. Physical-device startup and
timer sharing still require the user's confirmation; artifact inspection is not
an installed-device execution test. No backend/HA deployment, iOS/web build,
release tag or main merge was needed for this correction.

# Safe recipe retries and pending save reminders

Every new recipe create/edit outbox entry has a durable `client_save_id`. Its
request is replayed unchanged after a temporary network failure or process death.
The server atomically records the result with the recipe and returns the original
receipt on retries. This avoids duplicate creates and false revision conflicts
after a lost edit response. Actual conflicting edits or validation failures still
retain the local draft for review. Legacy ambiguous submissions without an
identifier cannot be retroactively deduplicated and remain reviewable.

Each local change stores its original save time. At 60 seconds without a server
confirmation, the app displays an overdue warning. It keeps the local recipe
visible. Android/iOS also schedule device notifications when the outbox persists,
so reminders do not require a reachable server or a running Flutter timer.
Confirmation cancels pending/delivered reminders. Restart retains the original
deadline; repeated retries do not restart it. Android restores reminders after
reboot/update. Notifications contain no recipe text or account identity.

Device notification permission is required. Denial or scheduling failure is
reported in the app; the in-app warning still works, including over an open editor. OS power/notification policy
can delay or suppress delivery, especially Android without exact-alarm permission.
iOS uses one reminder for the oldest outstanding change per account to avoid its
pending-notification limit. Web currently shows the in-app warning while open.
Background uploading remains subject to app lifecycle; reminders do not claim
that background Flutter code runs while the OS has suspended it.

Validation: the local-data suite covers same-identifier retries after a lost
creation response, process-death recovery, retained local data, original deadline
across restart, the one-minute boundary, and cancellation on confirmation. Main
full suite: 410 tests passed; feature full suite: 447 tests passed. Static
analysis passed. The overlay test verifies the warning over an open recipe editor;
the native bridge test verifies schedule/cancel payloads without recipe content.
Android notification Kotlin also compiled in isolation. Physical-device delivery
still needs verification; no phone was connected for this work.

## Requested main test builds, 2026-10-23

Both builds use clean main source `e87db52e8cd6563367bce59f1375b83e50f4f81a`,
version 1.8.5+29, the existing private Firebase configuration and coffeybean.com.
The subsequent documentation commit does not change their runtime source.

- Local web: `http://localhost/CoffeyTableRecipes/app/`. Served version metadata
  matches the source commit. HTTP-served main.dart.js matches the build output:
  SHA-256 `1e2be1c89f512a1ad84ecc219b1c5c7364b41c5f85cc267737b74d7209088f62`.
- Android debug test APK:
  `G:\My Drive\recipe app\CoffeyTableRecipes-main-local-sync-e87db52.apk`.
  Verified package `com.coffeytable.coffey_table_recipes`, versionCode 29,
  versionName 1.8.5, minSdk24, targetSdk36. Signature verification passed and the
  certificate matches the preceding test APK:
  SHA-256 `f8de933f14b9bb4b3191a94aedc8637972c5ab224565f6abd7808f8038d12097`.
  Shared copy matches the build output, 199846094 bytes:
  SHA-256 `4c3041a2d3ef1fbd3fe5996fc4fa515c4eb093128e03cad6fd2c2c1d7da3ff04`.

No release tag or hosted Flutter publication was performed. The hosted receipt
backend was separately deployed and verified in Actions run39998462691.

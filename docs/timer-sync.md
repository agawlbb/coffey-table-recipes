# Account timer mirroring

Timer settings has a per-installation, per-account **Receive timers from other
devices** switch, off by default. Sign-in and notification/alarm permissions are
required to enable it. It does not control sending: timers started locally are
published for the same account's enabled devices. Web and watches are outside
this implementation.

The originating alarm is scheduled before network work. A durable account-scoped
outbox preserves offline start/edit/cancel operations and their operation IDs.
Other devices receive the same absolute deadline, never a restarted duration.
The PHP API owns revisions and rejects conflicting edits. Android applies data
pushes in a native FirebaseMessagingService; iOS applies pushes in AppDelegate.
Reopening or resuming reconciles server state; foreground fallback polls every
20 seconds. Received operations never publish themselves again.

Mirrors use `remote:<origin installation>:<recipe>:<action>` keys, avoiding
collisions with independently started timers on another device. Updates to a
mirrored timer retain its shared ID. Disabling reception removes received alarms
on this device without cancelling the originating alarm. Sign-out/account change
clears account timers and native reception before server unregistration; delayed
pushes must match both the current account and installation.

Native revision markers are written after successful OS scheduling/cancellation.
An exception leaves the revision retryable. This is local confirmation only:
there is **no sender-facing remote-scheduling acknowledgement badge** in this
version. FCM acceptance must never be described as proof another device scheduled
an alarm. Server push failures leave the timer saved, with a warning in Timer
settings; other devices recover by reopening. A timed-out write retries the same
operation and can resend the same revision safely.

## Configuration before device acceptance

- Firebase Cloud Messaging HTTP v1 was verified enabled on 2026-10-17 for
  `coffey-table-recipes`. The Apple Firebase registration has topic-specific APNs
  development and production authentication keys installed.
- APNs keys are installed in Firebase for
  `com.coffeytable.coffeyTableRecipes`, Push Notifications is enabled on that App ID;
  Regenerate provisioning through the established signed release workflow.
  Runner has the push entitlement, remote-notification background mode and Xcode
  capability. App extensions do not need push capability. Distribution signing
  must use the production APNs entitlement/profile.
- Configure the PHP sender's separate least-privilege credential as described in
  the backend `docs/timer-sync.md`. Never broaden the auth-lookup account's role.
- Android native Firebase options come from the existing release Dart defines
  through Gradle resource values, allowing FirebaseInitProvider to initialize on
  a cold push launch. No Firebase configuration file is tracked. The explicit
  native messaging dependency uses the locked firebase_core BOM (34.19.0); review
  it when upgrading firebase_core. The Flutter messaging receiver/service are
  removed from the merged manifest in favor of the native timer service.

Apple can delay or omit background execution. A generic visible start/update
notification provides an open-app recovery path; tapping it and foreground
reconciliation schedule the remaining time if still in the future. Cancellation
pushes are silent and may also be delayed. Once a device has scheduled a timer,
its local alarm can work offline, but offline edits/cancellations cannot propagate
until connectivity returns. Previously queued generic Apple notifications can
still arrive after opting out while offline. Do not promise immediate mirroring,
force-stop delivery, or alarms while powered off.

## Validation and release boundary

Flutter analysis and timer unit/widget tests cover persistence, opt-in/off,
offline restart recovery, original deadlines, cancellation identity/revisions,
account binding, sign-out while offline and native scheduling failures. Backend
tests use disposable SQLite memory and fake push transport; migration tests mock
cPanel and verify privilege restoration and exact-job cleanup.

No app build is authorized by this feature request. Kotlin/Swift compilation and
physical-device push delivery are therefore still unverified. Before release,
test iPad→Android, Android→iPhone, iPhone→iPad with screens locked and apps open,
backgrounded and terminated. Check permission denial/revocation, APNs development
and production, time zones, duplicate/reordered pushes, two simultaneous timers,
offline start/edit/cancel, reconnect, reboot, account switching, and existing
AlarmKit versus older-iOS local-notification behavior. Confirm no alarm is shown
as ready after an OS permission failure.

Validation on 2026-10-17: all 297 Flutter unit/widget tests passed; final focused
coordinator/settings tests and Flutter analysis passed. Backend validation passed
all 22 workflow PHP fixture scripts, six migration checksum checks and all 99
Python deployment/migration fixture tests. Native compilation/device acceptance
remains pending an explicitly authorized build.

Hosted setup verified on 2026-10-17: the dedicated sender has only cloudmessaging.messages.create. Its credential is protected with mode 0600 and public HTTP access returns 403. Hosted OAuth and FCM validate-only authorization passed without sending a notification. The uploaded Google key expires 2027-10-17 and must be rotated before then. Both unused download keys were deleted after verification. Native compilation and physical-device delivery remain unverified.

## Android test APK — 2026-10-17

At the user's explicit build request, generated Android debug version 1.7.0,
build 23 from app source ed5b053 plus the Android resource-generation fix.
The current Android Gradle plugin requires buildFeatures.resValues=true for
Firebase's cold-start resource values; compilation passed after enabling it.
Generated Android build reports are ignored.

Verified APK signature matches the existing app certificate
F8:DE:93:3F:14:B9:BB:4B:31:91:A9:4A:ED:C8:63:79:72:C5:AB:22:45:65:F6:AB:D7:80:8F:80:38:D1:20:97.
Package metadata confirms com.coffeytable.coffey_table_recipes, version 1.7.0,
build 23, minimum API 24 and target API 36. The merged manifest contains the
native TimerSyncReceiver and omits FlutterFirebaseMessagingService.
Delivered G:\My Drive\recipe app\CoffeyTableRecipes-1.7.0-build23-timer-sync-test.apk;
source and destination SHA-256 match:
d36314204e92ad1fcd2294c5a54b2e01a79258536083c2298e46ec79383fad77.
No release/tag, app push, web deployment or iOS build was performed. Android
native compilation is now verified; physical-device delivery and audibility
remain pending installation and an account-scoped test send. iOS compilation
remains unverified.

## Release 1.8.0/build 24 — 2026-10-18

The requested release now verifies Android and iOS native compilation. The iOS
distribution IPA passed actual signature/profile checks, including production
APNs on Runner and hosted universal-link identity, before Xcode uploaded from the
same archive. See `releases.md` for build and TestFlight processing evidence.
Android cold/warm recipe links passed on the release APK in the existing emulator.
These checks do not establish cross-device push delivery, locked/background
execution, alarm audibility or physical-iPhone behavior; the device acceptance
matrix above remains outstanding. No timer notifications were sent during release
validation.

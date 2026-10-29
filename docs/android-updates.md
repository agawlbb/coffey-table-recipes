# Android Drive distribution and release announcements

Work remains on `feature/android-drive-distribution`, originally based on fetched
app `origin/main` `fe83d03`. APK distribution stays in Google Drive. Android
receives a notification advising that a newer version is available there.
Notifications have no link or click action because recipients may use different
shared Drive locations. The automatic update window, startup/resume metadata
checks and VPS APK hosting remain removed. Timer notifications and navigation
are preserved. No new dependency or user-facing control is introduced.

After Firebase initialization, Android requests notification permission and
subscribes to `android_releases` without delaying startup. It is independent of
sign-in/timer sharing and retries registration on the next launch after failure.
iOS/web skip registration. Native reception checks the installed build and
version format before displaying the informational App updates notification.
Current/newer installed builds and denied notification permission suppress it.

Android delivery uses the existing Google Drive **recipe app** folder. The
publisher requires a privately configured rclone OAuth remote and exact folder
ID, refuses ambiguous/conflicting releases, uploads the signed APK, downloads
and verifies SHA-256, and only then trashes precisely named lower-build release
APKs in that folder. Existing release filenames are verified before reuse.
Unrelated files, subfolders, inspection APKs and signed iOS files are preserved.
No Google sharing permissions are changed. After uploaded-byte verification,
the publisher sends the Android-only FCM announcement, writes a private atomic
mode-600 receipt, and then removes older authorized releases. Notification
failures preserve older files for retry; repeat publication or cleanup retry
reuses the send receipt. Lost FCM responses/receipt writes can permit a duplicate
send, but a fixed native notification ID replaces earlier notices. A newer or
conflicting receipt is rejected rather than overwritten.
See [current publication/setup instructions](releases.md#android-publication-and-automatic-cleanup).

VPS infrastructure changes are on the matching branch in `vps_admin`, based on
`175e465`. Caddy APK/metadata routes and the read-only package mount were removed
from source and the live service. Caddy validation/recreation passed. Stable
and versioned APK URLs plus `latest.json` now return 404; FlightSync remains
200. Caddy retains production shares 1024 and unlimited effective CPU quota.
The public APK/link/metadata have been removed. The signed 2.3.0/build 39 APK
was retained privately with a verified checksum and subsequently copied to Drive;
it was not rebuilt. The VPS runbook records backup/rollback paths.

rclone v1.75.2 is installed privately after checking the official release
SHA-256. The initial all-Drive authorization was stopped without saving credentials.
The replacement uses only `drive.file` and Google's OAuth-integrated Picker,
excluding prior broader scopes and requesting offline renewal. Its actual Google
redirect parameters were inspected and verified. The tracked one-time helper
`tool/authorize-google-drive.py` stores the resulting refresh token privately;
future releases need no laptop. The publisher rejects full/missing/mixed-scope
configurations and a destination different from its configured recipe folder.
The recipe folder ID is user-provided and pinned to
`1VM1K1Ge6sgjEjtoEjS7aGzHYiSzlLVE-`. On 2026-10-29, Google consent
completed and the OAuth config was verified mode 600 with a refresh token.
Direct Google metadata readback confirmed the ID, name **recipe app**, folder
MIME type and upload capability. A disposable probe was uploaded, downloaded,
SHA-256 checked, moved to Drive trash, and confirmed absent from the live listing.
No pre-existing Drive file was modified by that check.
A forced-expiry test then confirmed that rclone renews access from the VPS's
stored refresh token without a browser, SSH tunnel or laptop. The existing
signed 2.3.0/build 39 APK was published with the actual publisher and its
uploaded bytes were downloaded and verified:

- [Verified existing 2.3.0 APK](https://drive.google.com/file/d/1mNnSFKwYrEigaJf94mIr9Jnr744yUf2J/view).
- SHA-256: `e6915b67ecda537a6127a92d315c32eb59fc2bc8e8e5409f325668f26d81bf2b`.
- Publisher result: no older authorized APKs were visible; zero were trashed.
- Drive sharing was preserved; no app package was built and no new version was
  tagged or released. This APK retains its original 2.3.0 code; removal of the
  update feature takes effect only in a later authorized build from this branch.
 Existing child APK access is not assumed from
folder selection alone; existing legacy files must be selected explicitly if
they are to be cleaned up by this credential.
The existing Firebase messaging credential is reused privately by the release
publisher. OAuth and FCM validate-only authorization passed for the actual new
payload on 2026-10-29; no notification was delivered by this check. The existing
2.3.0/build 39 artifact's hash was checked before initializing its private
notification baseline, so this already-delivered version is not reannounced. Installed 2.3.0 apps retain their prior code until a later
explicitly authorized release is installed; the former update endpoint is now
unavailable and its existing client silently ignores that response.

Focused validation through the shared development container:

- `dart format lib/main.dart lib/src/android_release_notifications.dart test/android_release_notifications_test.dart`.
- `flutter analyze --no-pub lib/main.dart lib/src/android_release_notifications.dart test/android_release_notifications_test.dart`: no issues.
- `flutter test --no-pub test/android_release_notifications_test.dart test/timer_sync_test.dart test/account_timer_menu_test.dart test/recipe_timer_navigation_test.dart`: 14 passed.
- `python3 -m unittest tool/test_publish_android.py`: 23 passed, including Drive failure preservation, duplicate/conflicting releases, restricted config, notification ordering/failure/retry, repeat-send suppression, scoped OAuth and validate-only payloads.
- Manual native-source review confirms there is no notification click intent or URL, startup metadata check or update dialog. Native Android compilation/device receipt have not been verified in this task.
- No app build, tag, app deployment, device installation or live broadcast is part of this task.

Keep the branch for user review; no automatic merge to main is intended.

## Historical update feature (superseded)

The following evidence describes the rejected implementation before removal.

# Android release updates

Task `task/android-release-updates` starts at app commit `1680c0c` from fetched
`origin/main`. It retains VPS APK distribution and adds update detection without
new package dependencies, backend APIs or database changes.

The app subscribes to the Android-only `android_releases` Firebase topic and
requests notification permission separately from timer sharing. The existing
native Firebase receiver checks the installed Android build before posting an
App updates notification. Foreground/background delivery uses the same native
path, including when Flutter is stopped. Tapping opens the app. Topic delivery
is a hint; opening/resuming checks the authoritative public `latest.json` even
when signed out or notifications are denied. Only a higher build and the exact
trusted VPS download URL can present the dismissible update dialog. The URL is
selectable, Download update opens the external browser, and browser failures
show a retry message. Offline and malformed responses leave the app usable.
Android handles APK installation; no automatic installation is attempted.

The publisher validates both public APK downloads before writing metadata and
sending the topic push. Push failures preserve old packages and permit retry;
a private receipt suppresses repeat sends after successful publication. A lost
FCM response/receipt can result in a repeated push; the native notification ID
replaces the previous notification. Newer or already installed builds ignore it.
Only public release data appears in payloads and metadata. See
[release instructions](releases.md#vps-release-setup) for the sender credential
and command. The sender uses short-lived scoped OAuth, Python's standard library
and OpenSSL; credentials are never included in Git or the public directory.

Caddy previously allowed APK filenames only. The separate `vps_admin` task
adds exactly the metadata URL. Its validation and live checks confirm JSON MIME,
no-store caching and the existing APK/private-path behavior. The endpoint is
seeded with the existing 2.2.1/build 38 verified APK; no new release was announced.

Validation on 2026-10-29, through the shared development container:

- `dart format lib/src/android_updates.dart lib/src/app.dart test/android_updates_test.dart`.
- `flutter analyze --no-pub lib/src/android_updates.dart lib/src/app.dart test/android_updates_test.dart`: no issues.
- `flutter test --no-pub test/android_updates_test.dart test/timer_sync_test.dart test/account_timer_menu_test.dart test/recipe_timer_navigation_test.dart`: 16 passed.
- `python3 -m unittest tool/test_publish_android.py`: 11 passed, including publication ordering, failure preservation/retry, repeat-send suppression, scoped OAuth and Android topic payload.
- Diff/links reviewed. An initial test command included nonexistent `test/widget_test.dart`; the corrected command above passed.

No app build, tag, app deployment or device installation was performed.
Native Android compilation, real push delivery, notification tapping and APK
installation require a future explicitly authorized build/release and a physical
device. Installed 2.2.1 clients need a manual update to the first release carrying
this feature before they can subscribe. The user copied the existing inMotion timer sender credential to the private VPS
path `/home/debian/projects/.release-tools/credentials/timer-push.local.json`.
On October 28, 2026 (America/New_York), mode 600, the matching Firebase project,
OAuth and FCM `validate_only` authorization passed with the publisher's exact
Android topic payload. No notification was sent; the inMotion credential was
not changed. This establishes sender authorization, not device delivery.
Verification documentation task `task/verify-android-push-credential` starts at
fetched `origin/main` commit `d9dcc67`; documentation-only diff/link review is
sufficient and no app checks or builds were repeated.

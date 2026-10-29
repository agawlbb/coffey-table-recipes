# Android distribution change

The user rejected the Android update-notification process and requested work on
`feature/android-drive-distribution`. This branch starts at fetched app
`origin/main` `fe83d03`. It removes the Android-only Firebase release handler,
release-topic subscription/notification permission request, startup/resume
metadata checks, update dialog and its feature-specific tests. Account-private
timer notifications and navigation remain in place. No dependency was removed
because Firebase messaging, package info and URL launching have other callers.

Android delivery uses the existing Google Drive **recipe app** folder. The
publisher requires a privately configured rclone OAuth remote and exact folder
ID, refuses ambiguous/conflicting releases, uploads the signed APK, downloads
and verifies SHA-256, and only then trashes precisely named lower-build release
APKs in that folder. Existing release filenames are verified before reuse.
Unrelated files, subfolders, inspection APKs and signed iOS files are preserved.
No Google sharing permissions are changed and no release push is sent.
See [current publication/setup instructions](releases.md#android-publication-and-automatic-cleanup).

VPS infrastructure changes are on the matching branch in `vps_admin`, based on
`175e465`. Caddy APK/metadata routes and the read-only package mount were removed
from source and the live service. Caddy validation/recreation passed. Stable
and versioned APK URLs plus `latest.json` now return 404; FlightSync remains
200. Caddy retains production shares 1024 and unlimited effective CPU quota.
The public APK/link/metadata have been removed. The signed 2.3.0/build 39 APK
was retained privately with a verified checksum for later Drive transfer;
it was not rebuilt. The VPS runbook records backup/rollback paths.

rclone v1.75.2 is installed privately after checking the official release
SHA-256. Browser authorization is in progress; the destination folder ID and
live Drive upload/download/trash checks remain pending the owner's consent.
The existing Firebase credential stays private and is no longer needed by the
release publisher. Installed 2.3.0 apps retain their prior code until a later
explicitly authorized release is installed; the former update endpoint is now
unavailable and its existing client silently ignores that response.

Focused validation through the shared development container:

- `dart format lib/src/app.dart`: no changes needed.
- `flutter analyze --no-pub lib/src/app.dart`: no issues.
- `flutter test --no-pub test/timer_sync_test.dart test/account_timer_menu_test.dart test/recipe_timer_navigation_test.dart`: 10 passed.
- `python3 -m unittest tool/test_publish_android.py`: 14 passed, including upload/download failure preservation, unchanged-filename retry, duplicate names, downgrade/conflict refusal, missing IDs and cleanup failure.
- Manual native-source diff confirms only the release-update handling was removed.
- No app build, tag, app deployment or device installation is part of this task.

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

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
this feature before they can subscribe. The VPS has client Firebase configuration
but no identified messaging service-account file; sender setup/live verification
remains pending that credential. Existing backend timer credentials are kept
separate and have not been changed.

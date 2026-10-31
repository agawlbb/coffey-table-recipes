# Child-mode policy on the VPS

`feature/vps-account-auth` moves the authoritative policy into `users.child_mode`
in the existing hosted MySQL database. The row also holds the PIN hash, failed
attempts, lockout deadline and pending administrator-reset timestamp. Plaintext
PINs are never stored. Row locks serialize changes and preserve failed-attempt
updates even when a PIN is rejected.

The app routes `/me/child-mode` and `/admin/users/{id}/reset-child-mode` through
the VPS account WebSocket scope. Policy reads include only linked people in the
requester's households. Reset requires an application administrator and explicit
confirmation; it clears the policy only after the target signs in again, matching
the existing behavior. Shopping retains its existing UI enforcement.

The VPS reads SQL directly during signup, sign-in and verification. There is no
InMotion PHP policy HTTP call. The existing authenticated SMTP relay is retained;
the database itself remains hosted on InMotion. Existing account administration
outside the PIN/reset paths remains in its separate backend.

One-time setup uses the shared server's `020_child_mode.sql` and imports the legacy
protected file state. Source files are retained. Routine deployment does not run
schema changes or repeat the import. The shared policy HTTP endpoints retire, and
retained shared-backend write guards read the same SQL state.

App validation: changed Dart files formatted and scoped analysis passed; 33 tests
passed across backend sockets, child mode, verification and invitations. The full
`flutter test --no-pub --reporter compact` suite passed all 549 tests once after the
final app routing changes. Backend cutover added five columns, preserved/imported
all three existing policies for four users, verified values and restored original
database privileges. VPS source `c9db933` is deployed and live SQL policy reads and
WebSocket checks passed. The old account/PIN/reset HTTP routes are retired. No web
frontend build was made; its old HTTP account routing is no longer supported.

Android test `2.4.0-account-test`, build 43, was built from immutable app source
`044b1986dff5e4c785388c972d5b4a9459be87c8`.
[Build 41212746459](https://github.com/agawlbb/coffey-table-recipes/actions/runs/41212746459)
passed original signing identity, package/version/source and hosted app-link checks.
Independent local APK verification and downloaded Drive bytes matched SHA-256
`b71f6428d9e5bfa051ba29cfc3fd6a26b6d574a03a8cca892555f93ea5874176`.
[Download build 43](https://drive.google.com/file/d/1Jtf6XkhIv4Cebfs2w6hsYg-4td43y2fE/view).
The usual private pinned Drive folder was used, Android devices received the
informational notification, and only the exact superseded build-42 test APK was
moved to trash after verification. Stable build 40 and unrelated files were
preserved. No sharing, main-branch merge, iOS/web build or VPS APK-metadata change.
Install this APK over the current app and retry account setup/verification.

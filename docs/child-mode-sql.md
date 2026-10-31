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
passed across backend sockets, child mode, verification and invitations. Full-suite
and Android build-43 delivery evidence will be recorded after completion.

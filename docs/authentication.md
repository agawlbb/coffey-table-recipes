# Authentication and household checkpoint

Firebase project: `coffey-table-recipes` (Spark plan). Android and web registered. Email/password and Google providers enabled, debug SHA-1 and SHA-256 added. Firebase Hosting, Analytics, and optional Gemini assistance are not used. Localhost is authorized.

Email access supports sign-in, account creation with name and password confirmation, and password reset. New passwords require at least eight characters in the client. Firebase manages passwords; the PHP server receives only ID tokens. Enter your own new password in the app. Google remains an optional sign-in method.

## Run

Firebase client settings are in ignored `config/firebase.local.json`. Start Android with:

```powershell
flutter run -d emulator-5554 --dart-define-from-file=config/firebase.local.json
```

Run web locally with `tool/publish-local-web.ps1`, then open `http://localhost/CoffeyTableRecipes/`. The script includes local Firebase settings when present. For a new checkout, fill out `config/firebase.example.json` and save as `config/firebase.local.json`. Do not put service-account private keys in any client build.

Firebase is initialized using explicit platform-specific FirebaseOptions. Native Google sign-in uses the web OAuth client ID as serverClientId. Client JSON and native configuration files are ignored according to the project's configuration policy.

The iOS source retains `com.coffeytable.coffeyTableRecipes` (Flutter's generated Apple identifier). iOS Firebase registration, plist, URL scheme, and macOS verification remain to be completed before iOS sign-in is usable. Android uses `com.coffeytable.coffey_table_recipes`.

## Backend boundary

- `GET /me`: verify Firebase identity, provision/retrieve local user, return only their household memberships.
- `GET /households`: retrieve current user's households.
- `POST /households`: transactionally create household, owner membership, and linked household person. JSON fields: name, person_name.
- `GET /households/{id}/people`: require membership before querying people.
- `POST /households/{id}/people`: require owner/admin; create a person without a login. JSON field: display_name.

Identity comes only from the verified token, never a client-supplied UID. Wrong-household access returns 404. Member writes to the people list return 403. Authentication errors return 401 and prompt one token refresh in the client. Database IDs are JSON strings to preserve precision on web.

The firebase/php-jwt package verifies RS256 signatures. Application checks enforce Firebase audience, issuer, subject, expiration, issued-at/authentication times, and Google or password provider. Public signing certificates are retrieved with TLS verification and cached according to Google's max-age header. Verification does not require a service-account private key.

Firebase refresh-token revocation is not queried on each request; an otherwise valid issued ID token remains usable until its expiry. Local users.disabled is checked on every protected request and can immediately deny app access. Use HTTPS outside local prototyping.

This checkpoint creates households and tracks people. Household invitations, membership management, recipes, and notifications are subsequent features.

## Verification

```powershell
flutter analyze
flutter test
flutter test integration_test/foundation_test.dart -d emulator-5554 --dart-define-from-file=config/firebase.local.json
C:\xampp\php\php.exe C:\xampp\htdocs\CoffeyTableRecipes\tests\authentication.php
```

The PHP tests generate signing keys in memory and create/drop a dedicated randomly named test database, leaving household data untouched. They validate signature/claim rejection, isolation, roles, account disabling, multiple households, and people without accounts. They do not replace a real Google sign-in test.

Official references: [Flutter Google sign-in](https://firebase.google.com/docs/auth/flutter/federated-auth), [server ID-token verification](https://firebase.google.com/docs/auth/admin/verify-id-tokens).

## Emulator keyboard and published UI

The CoffeyTable Pixel 8 emulator supports computer-keyboard input with `hw.keyboard=yes` in its local AVD configuration. Restart the emulator after changing this setting, click a text field, and type using the computer keyboard. Android's `show_ime_with_hard_keyboard=0` setting keeps the software keyboard hidden when a hardware keyboard is available. No credentials are stored in project files.

Source changes do not update the XAMPP copy automatically. Run `tool/publish-local-web.ps1` to rebuild with the ignored local Firebase configuration and publish the assets, then refresh Chrome at `http://localhost/CoffeyTableRecipes/app/`. Use Ctrl+Shift+R if an already-open tab still displays the previous design.

## Household and people screen (2026-10-10)

The app presents one household per account. Accounts without a household still use the initial setup form. Household creation rejects an account that already has a membership; the membership schema remains capable of multiple households. Legacy accounts with several memberships use the oldest household (lowest ID) and have no household selector. Existing memberships are retained.

Household & people displays the household name and an always-visible people list. Owners/admins can rename the household and add people through name dialogs. Linked people have a filled account-circle icon beside their name with no hover label; people without accounts have an envelope invitation button in the same left-hand icon position that announces invitations are coming later. The rows have no visible account-status labels. Adding a person does not create or invite a login account.

Renaming uses authenticated `POST /households/{id}/name` with JSON `name`, returning `household` with `id`, `name`, and `role`. The server requires owner/admin access and validates the name. No schema migration is needed. The app continues to use coffeybean.com; the matching PHP endpoint must be deployed there before hosted rename works.

Validation: Flutter widget coverage includes narrow/wide layouts, one-household presentation, visible people, account/invitation icons, name validation, renaming and adding a person. PHP tests verify creation rejection, persisted rename, permissions and household isolation while retaining the multiple-membership schema test.

On 2026-10-10 the live localhost browser reproduced invisible new icons caused by reusing a cached icon-font subset. Local publishing now gives font files content-specific URLs in FontManifest.json and sends no-store headers. Visual verification in the signed-in Chrome session confirmed the user's account icon, the user's envelope button, the add-member icon, and the invitation placeholder feedback.

## Your name at the table

The user menu separates Change name at the table from Change account display name. The table-name editor uses authenticated POST /households/{id}/people/me/name with display_name; the server selects the person from the authenticated account, never a client-supplied user ID. It preserves the member ID and updates only that household. Members can edit their own names; the app shows an edit icon only beside their own person. Names are trimmed, required, and limited to 200 characters. No migration is required. The apps remain on coffeybean.com; deploy index.php and src/HouseholdService.php together before using this option. Widget coverage checks independent account/table names, validation, saved row updates, and failure feedback. PHP disposable-database checks cover persistence, member access, missing person records, and household isolation.

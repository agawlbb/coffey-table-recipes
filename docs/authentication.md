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

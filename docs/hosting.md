# Hosted testing deployment

The default API for Android and web is `https://coffeybean.com/CoffeyTableRecipes/api/v1`.
Only the backend is deployed to coffeybean.com. The web app remains in local XAMPP.
Android needs only internet access; a locally served web page still needs access to the laptop that serves it.

## Local copies

The PHP project and original database remain in XAMPP. Hosted and local data are independent copies; edits are not synchronized automatically. The local published web app also uses the hosted backend by default.

Before future API or database schema changes, ask whether to switch back to local development. After that decision, select a local endpoint with a build-time `API_BASE_URL` override, for example `http://10.0.2.2/CoffeyTableRecipes/api/v1` for an emulator or `http://localhost/CoffeyTableRecipes/api/v1` for web. Include `--dart-define-from-file=config/firebase.local.json` as usual.

## Build

```powershell
flutter build web --base-href=/CoffeyTableRecipes/app/ --dart-define-from-file=config/firebase.local.json
flutter build apk --debug --dart-define-from-file=config/firebase.local.json
```

The APK is a debug-signed testing build. Install it over the prior debug build on the test phone. Generated builds and Firebase configuration stay out of Git.

## Verification on 2026-10-09

Flutter analysis and all 12 tests passed. Web and Android debug builds succeeded. Hosted health returned healthy JSON with browser and Dart user agents. The authenticated local web session read its household, recipe list, and recipe detail through the hosted API. The local web page displayed the connected service state.

The initial database copy contained 17 tables and 187 rows; every hosted table count matched its local source. Remote backend internal directories returned HTTP 403. No other domain directories or databases were changed.

# Hosted testing deployment

The default API for Android and web is `https://coffeybean.com/CoffeyTableRecipes/api/v1`.
The 0.1.0 demonstration publishes the web app to `/CoffeyTableRecipes/app/`, reached through `/CoffeyTableRecipes/`. The local XAMPP copy remains available.
Android needs only internet access; a locally served web page still needs access to the laptop that serves it.

## Local copies

The PHP source remains in XAMPP, but the persistent backend and MySQL database are hosted exclusively on coffeybean.com. The outdated local recipe database was removed on 2026-10-11 after saving an ignored recovery backup in the backend repository storage directory. The local published web app continues to use the hosted backend.

Use coffeybean.com for future backend and database work. Only use a local endpoint for an explicitly requested isolated test, with a build-time `API_BASE_URL` override, for example `http://10.0.2.2/CoffeyTableRecipes/api/v1` for an emulator or `http://localhost/CoffeyTableRecipes/api/v1` for web. Include `--dart-define-from-file=config/firebase.local.json` as usual.

## Build

## Deployment on explicit release requests

`.github/workflows/deploy-web.yml` builds and deploys web assets only when manually dispatched at the user's explicit request, selecting a pushed release tag such as `v0.4.0`. Commits, branch pushes and tags alone do not deploy. The command "create a release" authorizes this explicit dispatch after tagging the release. It runs analysis/tests, uses the existing private Firebase build secret, gives fonts content-specific filenames, and verifies hosted source metadata and asset hashes after publishing. Deployments are serialized. Only the web `app/` directory is included in the archive; this workflow does not deploy PHP or migrations.

The workflow requires GitHub Actions secrets `CPANEL_USER` and `CPANEL_API_TOKEN`. The cPanel token has all API access granted to its account, not folder-limited access. Creating it and storing it in the private GitHub repository requires explicit approval. Do not commit the token or the cPanel password. Revoke or replace tokens from cPanel Manage API Tokens; an expiring token needs renewal before its expiry. The scripts use HTTPS with certificate verification and never log the credential.

The current website was manually published on 2026-10-10 from commit `76ba8d4`: version 0.2.0 build 3. Analysis and all 33 tests passed; the hosted JavaScript hash matched the local build.

Automatic deployment was activated and verified on 2026-10-10 by Actions run `38080431005`, deploying commit `2e74f48`. The approved token `codex-coffeytable-web` is stored only in the encrypted repository secret, with expiration on October 10, 2027 (local time). Its temporary local transfer file was removed. The workflow verified the absolute extraction directory, hosted source metadata, and all three checked asset hashes. Earlier unsuccessful setup runs were corrected before declaring automation ready. The workflow is now manual-only and requires a release tag, matching the user's requirement for explicit authorization plus a tagged version. It uses the stored token without a cPanel login.

```powershell
flutter build web --base-href=/CoffeyTableRecipes/app/ --dart-define-from-file=config/firebase.local.json
flutter build apk --debug --dart-define-from-file=config/firebase.local.json
```

The APK is a debug-signed testing build. Install it over the prior debug build on the test phone. Generated builds and Firebase configuration stay out of Git.

## Verification on 2026-10-09

Flutter analysis and all 12 tests passed. Web and Android debug builds succeeded. Hosted health returned healthy JSON with browser and Dart user agents. The authenticated local web session read its household, recipe list, and recipe detail through the hosted API. The local web page displayed the connected service state.

The initial database copy contained 17 tables and 187 rows; every hosted table count matched its local source. Remote backend internal directories returned HTTP 403. No other domain directories or databases were changed.

Unverified accounts now stay on a dedicated email verification screen after signup or login. Verification sends automatically, supports explicit resend and send-failure retry, and checks Firebase on return and every five seconds before showing household invitations/setup. Widget regression tests cover automatic sending, resend, retries and the absence of the old dialog choices. No backend API or database changes are required.

Verification screen published to localhost and coffeybean.com on 2026-10-10 from cfd6819. Flutter analysis passed; all 35 tests passed, followed by 8 verification/invitation checks after refreshing token claims. Hosted version.json, main.dart.js and FontManifest.json matched the final build by SHA-256. Real inbox delivery and verification-click testing still require a test recipient; widget checks send no email.

Verification delivery diagnostic: Firebase public project configuration omitted coffeybean.com from authorizedDomains, so the optional continue URL is rejected. Sending now retries without ActionCodeSettings only for unauthorized-continue-uri; Firebase hosted verification remains usable, but recipients return to the site manually until the domain is authorized. All 9 focused verification/invitation checks passed and analysis is clean. Firebase console access was denied for the built-in browser's signed-in account; no account verification status or permissions were changed.

Fallback build 492b743 was published to coffeybean.com and localhost. Hosted version metadata, JavaScript and font manifest matched the final build by SHA-256. The user confirmed the prior screen reported send failure. Inbox receipt has not yet been confirmed after deploying the fallback.

Verification resend policy: account creation sends the initial verification email once. Opening or reopening a verification screen/dialog, signing in, page refresh, and verification-status polling never send another email. Resending occurs only through the explicit resend button. All 9 focused checks passed; analysis is clean.

Dynamic Links shutdown review (2026-10-10): the app has no firebase_dynamic_links dependency, page.link URLs, passwordless email-link sign-in or Cordova implementation. Invitations use ordinary hosted URLs, while email verification sets handleCodeInApp=false and has no Android/iOS deep-link settings. Firebase's FAQ explicitly states web email actions are unaffected: https://firebase.google.com/support/dynamic-links-faq . Any future mobile email deep links require the current Authentication/App Links/Universal Links approach.

Signup send-result visibility: the auth screen can be removed before the initial verification request finishes. The verification screen now observes that same request through a notifier and shows success/provider errors without sending again. Signup captures the display name before auth navigation and saves it independently of email delivery. Analysis and all 10 focused tests passed; failure visibility and no extra sends are covered.

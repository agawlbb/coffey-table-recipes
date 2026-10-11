# Releases

## Release command

When the user says "create a release", review progress since the previous release, choose an appropriate version and increment its build number, validate and commit, create and push an immutable annotated tag, rebuild web/Android/unsigned iOS, explicitly dispatch hosted deployment using the release tag, and save the verified APK and unsigned IPA on the desktop. Then remove obsolete app release APKs and unsigned IPAs from the desktop, retaining unrelated files and signed packages. A tag by itself does not authorize hosted deployment; the web workflow is manual-only and requires a release tag.

## 0.4.0 — offline recipe library and browsing

Version `0.4.0+5`, tagged `v0.4.0`, adds an offline mobile recipe library and recent-photo caching, scoped recipes below distinct category cards, backend-delivered verification emails, and administration of Firebase-only accounts. The existing hosted verification backend is already deployed; this release rebuilds and distributes the app without database or backend changes. All three platforms share this version and build number; iOS is unsigned for user-managed signing.

The connectivity plugin requires the iOS 26 SDK. The iOS workflow selects Xcode 26.3 and supports manually rebuilding an existing release tag with updated workflow tooling, preserving the tag and application source.

Verified on 2026-10-11: analysis passed and all 60 Flutter tests passed. Android release compilation succeeded after regenerating plugin registration following tests. Web deployment run `38136744689` passed source metadata and asset verification; public metadata identifies `a6ded16`, version 0.4.0/build 5, and browser category browsing succeeded after a connection retry. Initial iOS compilation failed with the older SDK; corrected run `38137001260` checked out the unchanged `v0.4.0` source and successfully produced the unsigned IPA using Xcode 26.3. APK and IPA metadata both confirm version 0.4.0/build 5. Both packages were saved on the desktop, and the obsolete 0.1.0 APK found there was removed after replacement verification. Signing and on-device installation remain user-managed.

## 0.3.0 — email verification and administration

Version `0.3.0+4`, tagged `v0.3.0`, adds a dedicated email verification screen, explicit resend and refreshed verification claims before loading household invitations. Administration supports deleting accounts and unlinked table people. Android, web and unsigned iOS packages share this version and build number. The release tag publishes the hosted web app and builds iOS through GitHub Actions; signing and device installation remain user-managed.

Release verification on 2026-10-10: Flutter analysis passed and all 39 tests passed. Android release APK metadata confirms version 0.3.0/build 4. Hosted deployment run `38085019825` passed publication and asset verification; public version metadata identifies release commit `4ee5b75`, and the browser loaded recipe categories after a connection retry. iOS run `38085019826` built and packaged the unsigned IPA successfully. Both mobile packages were saved to the user's desktop; signing and on-device installation are pending.

## 0.2.0 — household invitations

Version `0.2.0+3`, tagged `v0.2.0`, adds household invitation dialogs, invitation responses after login, retry handling and duplicate submission protection. It targets the hosted coffeybean.com backend with the previously deployed invitation support.

Android release APK and unsigned iOS release IPA use the same version and build number. The iOS package is built by GitHub Actions for user-managed signing and installation. Validate with Flutter analysis and the complete test suite before distributing the builds. Generated packages and private Firebase configuration remain outside Git.

The initial demonstration is **0.1.0+1**, tagged `v0.1.0` in the app and backend repositories. It uses the hosted coffeybean.com API.

`pubspec.yaml` is the authoritative app version: `major.minor.patch+build`. Before 1.0, minor versions add demonstration features and patch versions fix bugs. Increment the integer build number for every distributed build. Reserve 1.0.0 for the first production release. Never move an existing release tag.

All platforms in a release use the same version and build number. Android demonstrations use the existing debug signing identity. iOS Actions packages an unsigned release IPA for later signing with Sideloadly; it is not directly installable. Firebase iOS registration and device testing are required before calling iOS ready.

Validate with `flutter analyze` and `flutter test`, build web and APK with the ignored `config/firebase.local.json`, then commit and create an annotated version tag. Push the commit and tag. The tag triggers the iOS workflow; its private artifact expires after 30 days, so keep a local copy.

The web entry is `/CoffeyTableRecipes/`, with assets in `/CoffeyTableRecipes/app/`. `app/version.json` records the version, build and source commit for deployment verification. Credentials, generated artifacts, signing identities and local Firebase configuration remain outside Git.

## 0.1.0 — initial demonstration

Household authentication, recipe categories and browsing, recipe details, cooking mode and navigation breadcrumbs. Hosted backend remains selected; no database or API changes are part of this release.

### iOS build 2

The iOS follow-up uses `0.1.0+2` and tag `v0.1.0-ios.2`; the initial `v0.1.0` tag remains immutable. Web and Android build 1 remain the published initial demo. The iOS workflow requires its Firebase client values and inserts the Google callback URL scheme during the build, keeping local client configuration outside source control. Sideloadly signing and on-device authentication must be verified separately.

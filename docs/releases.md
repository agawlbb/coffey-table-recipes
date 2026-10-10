# Releases

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

# Releases

The initial demonstration is **0.1.0+1**, tagged `v0.1.0` in the app and backend repositories. It uses the hosted coffeybean.com API.

`pubspec.yaml` is the authoritative app version: `major.minor.patch+build`. Before 1.0, minor versions add demonstration features and patch versions fix bugs. Increment the integer build number for every distributed build. Reserve 1.0.0 for the first production release. Never move an existing release tag.

All platforms in a release use the same version and build number. Android demonstrations use the existing debug signing identity. iOS Actions packages an unsigned release IPA for later signing with Sideloadly; it is not directly installable. Firebase iOS registration and device testing are required before calling iOS ready.

Validate with `flutter analyze` and `flutter test`, build web and APK with the ignored `config/firebase.local.json`, then commit and create an annotated version tag. Push the commit and tag. The tag triggers the iOS workflow; its private artifact expires after 30 days, so keep a local copy.

The web entry is `/CoffeyTableRecipes/`, with assets in `/CoffeyTableRecipes/app/`. `app/version.json` records the version, build and source commit for deployment verification. Credentials, generated artifacts, signing identities and local Firebase configuration remain outside Git.

## 0.1.0 — initial demonstration

Household authentication, recipe categories and browsing, recipe details, cooking mode and navigation breadcrumbs. Hosted backend remains selected; no database or API changes are part of this release.

# Account test deployment — 2026-10-31

The current Android test is [build 42](verification-delivery-fix.md), which fixes
the verification connection interruption and adds a resend cooldown. The build-41
delivery below is historical; its APK is no longer visible in the authorized
Drive listing.

The user authorized deploying the VPS feature branch and delivering a test Android
APK to the usual Google Drive recipe app folder. All three account branches remain
unmerged. The hosted web app and InMotion retirement branch were not deployed.

- VPS runtime source: `cecdda0d116ed3c27ff785b71369474f679f8495`.
  Source/dependency copy and restart succeeded; 47 deployed source/lock/asset hashes
  matched. Existing image reused, CPU shares 1024 and unlimited effective cpu.max.
  Existing SMTP/account credentials copied privately once; no new keys or rollback
  images. Firebase lookup, SMTP TLS/authentication and public WebSocket checks passed.
- Android source: `3d21ee2129439d94da33a17fa93c776772f9cd28` on `feature/vps-account-auth`.
  [Build 41208532860](https://github.com/agawlbb/coffey-table-recipes/actions/runs/41208532860)
  succeeded for `2.4.0-account-test`, build 41. Package identity, non-debuggable
  release mode, original signing certificate and hosted Android app association
  passed in CI and independent local APK checks. The initial dispatch with an
  incorrect source selector was cancelled; the linked job built the exact commit.
- APK: `CoffeyTableRecipes-2.4.0-account-test-build41.apk`.
  SHA-256: `01200705e5c2c21bec2cadf41ddc6fc96f157909ad52f0c12e2da0815d7d5be0`.
  Certificate SHA-256: `f8de933f14b9bb4b3191a94aedc8637972c5ab224565f6abd7808f8038d12097`.
- [Verified Drive test APK](https://drive.google.com/file/d/1B_QUXKwD_WBF_A4flHG5t4C-0WL8_26U/view).
  The destination was checked against the existing build-40 stable APK ID, using
  the private pinned folder configuration. Uploaded bytes were downloaded and their
  SHA-256 matched. An informational Android notification was sent; no link/click
  action or sharing change. Every pre-existing visible file, including the stable
  APK, was retained. No APK or update metadata was placed on the VPS.

Only the Android workflow changed for this build: an explicit test option accepts
an immutable commit and labels/increments the test package. Release-tag behavior
is retained. Embedded Python/shell syntax and immutable-source guards passed.
The application source retains the earlier passing 545 Flutter tests and focused
analysis; they were not rerun for workflow/documentation-only changes. No iOS or
web build was requested or started.

Install the APK over the existing Android app, sign out, then create an account
with a fresh email address. Check verification mail, follow its link, return to
the Android app and sign in. Create a household, sign out/back in and check it
persists. Existing password/Google sign-in and invitation acceptance can then be
checked. Real recipient delivery and signed-in device behavior have not been
verified by the deployment probes; no real verification email was sent by them.

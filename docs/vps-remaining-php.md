# Remaining VPS migration (source only)

Branch `feature/vps-remaining-php` starts at app main `8970194`. The subsequent user
request authorized deploying the VPS feature backend and building test Android
build 44. No merge or release was performed. Matching backend/HA branches are required; see
the [VPS cutover instructions](https://github.com/agawlbb/coffey-table-recipes-vps/blob/main/REMAINING-PHP.md).

The API base is `https://ctr.coffeybean.com/api/v1`. Account administration uses
the existing account WebSocket with progress. Recipe links use
`https://ctr.coffeybean.com/recipes/{id}`; only the new generated links are accepted.
Android/iOS associated domains and release checks target that host. Static Flutter
web files remain hosted on InMotion; this task does not move them.

The persistent account/cache namespace is deliberately retained so pending recipe,
meal and shopping edits survive the API address change. It is a disk key, not an
old-host network fallback. Cached owned-image URLs resolve to the VPS while
external image URLs remain unchanged. No controls or workflows were added.

Validation covers API/socket routing, generated links, offline restart and queued
upload, managed image URL boundaries and association source checks. Run the full
Flutter suite for this cross-cutting migration and analyze changed Dart files.
Native associations must still be checked against the actual signed packages and
installed-device link handling at the next authorized release.

Verified in the development container on 2026-10-31:

- `flutter test --no-pub`: all 559 tests passed. After the final link-input
  hardening, `flutter test --no-pub test/sharing_timers_test.dart`: all 3 passed.
- Changed Dart sources/tests formatted and analyzed: no issues.
- Focused API/cache restart coverage: 66 passing tests; initial focused
  API/socket/sharing coverage: 31 passing tests.
- Local Python Android/iOS association-tool tests: 3 and 6 passed. Actual VPS
  association JSON also validated against the existing released identities,
  Android manifest route and iOS entitlements. No network publish or device run.

## Feature test delivery — 2026-10-31

The VPS runtime is deployed from `03aa403d169ede87f0395805e702f65bc9199e44`.
All 83 VPS image files were verified over public HTTPS. All 65 owned photo records
now point to the VPS; 59 references were updated in the existing InMotion MySQL
database. All 75 original shared-host image files were retained. Daily cleanup
now uses the enabled VPS timer; the exact old recipe cron and the temporary export
job/files were removed, preserving the unrelated shared-host job.

Live health, rendered recipe GET/HEAD, missing-recipe 404, association JSON,
HA public configuration/auth boundary, private-path protection, public recipe
WebSocket read and heartbeat passed. Existing credentials and CPU policy remain.
Shared-host endpoint retirement and the HA integration update were not deployed.
Static Flutter web hosting and MySQL/SMTP remain on InMotion.

Live preflight required support for older 64-digit photo IDs and two named
illustrations in addition to newer 48-digit photos. The cached-image resolver,
backend migration/serving, cover reuse and cleanup were corrected. Focused app API
tests passed all 22 checks afterward, with changed Dart analysis clean. The earlier
559-test full-suite result remains the broad baseline; the final image-only changes
were verified with these focused checks and live image hashes, without rerunning
the full suite. No actual AI request was made by deployment verification.

Android test `2.4.0-account-test`, build **44**, was built from immutable source
`51cbee8a04c878857e88f1a2445764a8c65e2303`.
[Build 41226798187](https://github.com/agawlbb/coffey-table-recipes/actions/runs/41226798187)
passed. Superseded build attempts were not distributed.

- APK: `CoffeyTableRecipes-2.4.0-account-test-build44.apk`.
- SHA-256: `dc231c33f53fbfd9f5c68603d075b8804a61c4fa4c6f339a42ba6649742c6ef8`.
- Existing certificate SHA-256:
  `f8de933f14b9bb4b3191a94aedc8637972c5ab224565f6abd7808f8038d12097`.
- Package `com.coffeytable.coffey_table_recipes`, build 44, non-debuggable,
  actual compiled CTR host/recipe route and actual signing certificate verified
  independently with `aapt`/`apksigner`. The hosted association was checked against
  that certificate. This is not an installed-device link-resolution test.
- [Verified Google Drive APK](https://drive.google.com/file/d/1zIwcnyDs167RYbvu6nAJzsktpZAugzIH/view).
  The existing private publisher configuration was checked against the pinned
  recipe app folder and restricted Drive scope. Uploaded bytes were downloaded
  and SHA-256 matched. No existing Drive files were deleted or sharing changed.
  FCM accepted an informational Android notification with no link/click action.
  Device receipt and installation were not claimed as verified.

Build 44 was superseded by [corrected build 45](timer-preferences-startup.md),
which fixes the Android preferences release-startup failure and adds APK-level
JNI verification. Install build 45 over the existing app, preserving app storage.
Test existing sign-in, offline queued edits, recipe links/images, administration
and AI progress.
No iOS/web build, hosted Flutter deployment, main merge or release tag was made.

## Accepted merge — 2026-10-31

The user approved merging the remaining-PHP branches and removing them. Latest
app main (main dishes first per meal-planner date) was integrated before merging.
Focused meal planner, access, drag, backend socket and API tests passed, along
with analysis of the affected meal planner and API files. Earlier full-suite
validation remains recorded above. No app build or release is authorized by this
merge; release waits for AI dish chat. InMotion deployment is explicitly deferred.

# Remaining VPS migration (source only)

Branch `feature/vps-remaining-php` starts at app main `8970194`. No merge, app build,
release or deployment is included. Matching backend/HA branches are required; see
the [VPS cutover instructions](https://github.com/agawlbb/coffey-table-recipes-vps/blob/feature/vps-remaining-php/REMAINING-PHP.md).

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

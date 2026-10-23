# Local-first household data

Recipes, recipe browsing, favorites, people and shopping lists use persistent
device data as their primary read source on web, Android and iOS. The meal-plan
feature uses the same repository contract. Server response time must not decide
whether previously downloaded content is visible. Only a first download, a new
device, deliberately cleared storage, or confirmed access removal can lack local
content. A confirmed empty dataset is an empty state, not an endless spinner.

`LocalData` is scoped by API origin and Firebase account. It sits between the UI
and the API; `OfflineRecipes` supplies the full paginated recipe inventory,
details and category/search indexes. Web now downloads that inventory too.
Account startup also mirrors shopping lists, people, favorite membership and the
blank-recipe editor catalog. Browsing and recipe details observe local updates.
Background refresh is coalesced, throttled and limited to the latest watched
views, rather than polling every search the user has ever entered.
Foreground library synchronization checks complete recipe text/categories every
minute, including ingredient-only and instruction-only changes. The current API
inventory omits recipe revisions, so unchanged browse rows cannot prove unchanged
recipe content. Active shopping-list reads retain their five-second refresh
interval. A future revision/delta endpoint can reduce background traffic without
changing the local-first UI contract.

## Writes and synchronization

Ordinary recipe creates/edits, favorites and shopping edits commit a local
snapshot and outbox entry before returning success to the screen. Calendar
operations on the feature branch use the same durable outbox. Failed local
persistence rejects the edit; it must never claim a change is safely queued.
Queue processing is separate from UI reads and serial within a resource.
Confirmed revisions and server-assigned recipe/child IDs are carried forward
into dependent operations. New local recipe IDs resolve to canonical server IDs.

Server revision checks remain authoritative. A conflict preserves the device's
draft and exposes a comparison with the server version. The user can explicitly
apply the local edit against the reviewed server revision, or use the server
version and retain the local draft in the Saved local drafts view. A new remote
change after review still conflicts. An unresolved conflict does not block
independent resources. Account/membership rejection invalidates mirrored reads;
unsent drafts remain account-scoped for recovery.

The server has no general idempotency receipt for new recipe creation. If the
creation response is lost, or the app closes during synchronization, the outbox
requires review rather than automatically creating a duplicate. Revision-checked
updates and absolute favorite settings can retry without silently applying a
write twice. Never force a stale revision or rebase a conflicting edit without
the user's review.

Initial downloads and online-only operations still need the backend. These
include authentication/account administration, AI imports/variations/images,
recipe deletion/recovery/sharing and external shopping synchronization. Recipe
text and metadata are mirrored; image binaries retain the existing platform
image-cache behavior and are not guaranteed to be available offline. Web storage
is browser/origin-specific and can be cleared by the browser; it is not a backup.
The sync status reports storage/network failures instead of hiding saved data.

## Validation

`test/local_data_test.dart` covers restart with a hanging network, durable offline
edits, stale-response races, ordered revisions, account/server isolation,
permission invalidation, storage failure, local/canonical IDs, uncertain creation,
calendar-range reads, explicit conflict review and independent synchronization.
The existing widget suites cover recipe browsing/details and shopping behavior.
No app package build or hosted Flutter publication is part of this source change.

Main validation on 2026-10-23: full Flutter suite passed (389 tests), static
analysis clean. After final synchronization/access refinements, all 61 focused
local-data, offline-recipe and account-menu tests passed and analysis remained
clean. Workflows were inspected: the Flutter workflows are manually dispatched;
source pushes do not request a build or hosted publication.

Future screens must use local repository reads and local-change notifications.
Do not bypass this layer with a network-first load or clear a populated view
while synchronizing. Keep authoritative access checks and conflict handling when
adding new kinds of queued operations.

The shared repository is identical on main and the meal-planning branch. It also
protects against late read responses overwriting a newer acknowledged edit,
access-loss races, creation-ID transitions and stale copies after online recipe
deletion/restoration. The feature branch alone integrates full-calendar range
reads, household-filtered local pairings and local ingredient collection into
the planner UI; its feature-specific controls are not merged into main.

Final main verification on 2026-10-23: all 398 Flutter tests passed, static
analysis clean, and `git diff --check` clean. This includes the final shared
store, whole-library refresh, account integration and new synchronization-race
regressions. No app build, release tag, backend deployment or hosted Flutter
publication was performed.

Local test builds requested on 2026-10-23 were built from main source
`7c2225cbca171ddbb247807ced69ed023f47cd60`, version 1.8.5+29:

- Web: `flutter build web --no-pub --base-href=/CoffeyTableRecipes/app/ --dart-define-from-file=config/firebase.local.json`, followed by `tool/prepare-web.py`.
  Published only to ignored local XAMPP `app/`; localhost `version.json`
  returns the source commit above. Copied main.dart.js SHA-256 matches the build.
- Android: `flutter build apk --debug --no-pub --dart-define-from-file=config/firebase.local.json`.
  APK signature verification passed (Android Debug certificate SHA-256
  `f8de933f14b9bb4b3191a94aedc8637972c5ab224565f6abd7808f8038d12097`).
  Delivered `G:/My Drive/recipe app/CoffeyTableRecipes-main-local-first-test-7c2225c.apk`
  (174724489 bytes); source and delivered SHA-256 both
  `9fd5cf26116c9c35be023a615da0c7092eb686dabb103f6034f801afb81f105c`.

Both builds succeeded. Android emitted existing toolchain/plugin compatibility
warnings. No device installation test, release tag or hosted publication was
performed. Generated assets and private build configuration remain excluded
from Git. This build record is a subsequent documentation-only commit.

# Local-first household data

Recipes, recipe browsing, favorites, people and shopping lists use persistent
device data as their primary read source on web, Android and iOS. The meal-plan
feature uses the same repository contract. Server response time must not decide
whether previously downloaded content is visible. Only a first download, a new
device, deliberately cleared storage, or confirmed access removal can lack local
content. A confirmed empty dataset is an empty state, not an endless spinner.

`LocalData` is the single account/server-scoped persistent database used by production
screens. First use of this implementation and every newly joined household must
complete the blocking Downloading database screen. It displays received KB,
transfer fraction when Content-Length is available, and the saving stage. A missing,
invalid or interrupted response cannot mark the household ready. Retry downloads
the complete household snapshot; an already completed household remains usable.

The authenticated household snapshot endpoint returns recipe text and metadata,
category assignments/catalog, favorites, people, shopping list and editor catalog.
The feature backend also includes the complete calendar and history. Image bytes
are excluded. Database queries are batched by table rather than repeated per recipe.
A content hash covers instructions and ingredients as well as browse fields; unchanged
snapshots return only a version acknowledgment. A changed snapshot is validated,
written atomically, then published to screens, preserving dirty local resources.

After setup, recipe lists/categories/search/favorites and details are computed from
that same database. They never combine server pages and partially downloaded local
indexes. Screen reads do not initiate refreshes. Startup and one-minute foreground
synchronization update the database in the background; the outbox drains separately.
The first download is intentionally repeated for installations with only the old
partial cache. No completed-snapshot marker means setup is required, including for
an empty household (whose valid empty snapshot completes immediately).

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

Android sync-status follow-up (2026-10-23): periodic full-text revalidation
previously counted only recipes refreshed in that pass as locally available.
This repeatedly showed first-download preparation despite an existing mirror.
Progress now counts all persisted recipe text; missing initial downloads still
show preparation and failed synchronization still exposes its error. The status
badge says "Sync paused" because its triggers include API timeouts and temporary
HTTP failures, not just a disconnected device. The hosted API health endpoint
returned HTTP 200 in 0.18 seconds from the development machine; this does not
establish the cause of a device-specific request failure. All 47 offline-recipe
regression tests passed. No replacement APK or hosted app was built/published.

## Complete-database implementation validation (2026-10-23)

Main's full Flutter suite passed (402 tests); after final persistence validation,
all 28 affected snapshot/local-data/overlay tests passed. Snapshot tests cover
restart, repeated category reads with zero HTTP requests, replacement, failed
persistence, rejecting partial initial data and preserving pending shopping edits.
The former offline-cache download is disabled in production. Completed versions
are stored in LocalData; older caches never satisfy the initial setup gate.

## Complete-database test builds (2026-10-23)

Built main runtime `d5d04a88c97fe81178b30a1dd0fe61ce7038533f` (1.8.5+29).
Web build and Android debug build succeeded with the private Firebase define file.
Web assets were prepared with tool/prepare-web.py and copied only to ignored
local XAMPP app/. Served version.json confirms the runtime commit. main.dart.js
SHA-256 is d3c33a9c00f04b132fd41a48ed224f9d4efcb55a053f0969783432c1d4ca4479;
the delivered local web copy matches.

APK: G:/My Drive/recipe app/CoffeyTableRecipes-main-local-database-test-d5d04a8.apk,
199838785 bytes. Source/delivered SHA-256 both
9ae605f32d1d58cb239ece0d8434b20b2c2a686f86e52558ed08b64159ce5ffc.
APK signature verification passed with the existing Android Debug certificate
(f8de933f14b9bb4b3191a94aedc8637972c5ab224565f6abd7808f8038d12097).
No device installation test, release tag or hosted Flutter publication occurred.
Feature runtime 92a9442 has the same LocalData/API/snapshot tests; its planner
integration additionally requires calendar/history and disables its older downloader.
Its full suite passed 440 tests; final affected checks and source analysis passed.

Hosted backend e2bc05982ab3a29a2fce9692a507b2818dbab51d was published through
successful Actions run39991103386 while preserving planner routes. Its receipt
matches; the snapshot HTTP endpoint returns401 authentication_required without a
token. Backend snapshot/SQL fixtures and118 mocked deployment checks passed.
An optional privileged hosted-data probe was rejected by automatic approval
review (temporary PHP/cron and household-data access); it was not executed.
Authenticated on-device download remains unverified. Builds contain the actual
complete-database implementation, rather than just the earlier status correction.

Normal signed-in local web verification also passed after publication: parent
and leaf categories, repeated return visits to the same leaf, and complete recipe
ingredients/instructions displayed successfully through the app's normal session.
No hosting credentials or privileged probe were used for this web check.

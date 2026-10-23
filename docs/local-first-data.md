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

## Meal-planning branch integration

The feature branch mirrors the full supported calendar (2000-01-01 through
2199-12-31) once, then serves visible ranges from it. A range change never needs
a new download to display already mirrored meals. Add/move/remove update the
local calendar immediately, persist their ordered revisions and survive restart.
The planner observes repository changes; refresh does not hide a loaded calendar,
including a confirmed empty plan. Pairings and shopping ingredients are derived
from mirrored recipe/meal data, including pending local calendar edits.

Past-date confirmation and shared-recipe confirmation remain explicit. If the
server requires confirmation during synchronization, the local draft stays in
Review and can only be reapplied after the user reviews that request. Household
access rejection clears action readiness; late authorized responses cannot
restore revoked data. Existing drag scrolling, trash drops, dated recipe picker,
variation confirmation, unscheduled meals and ingredient selection are retained.

Feature validation on 2026-10-23: full suite passed (433 tests). After the final
whole-library refresh and household-filtered pairing changes, all 94 affected
local-data, offline-library, planner/access and Add recipe tests passed. Analysis
is clean. Backend source/schema and the experiment branch remain unchanged; no
app build or deployment was requested or performed.

## Complete-database implementation validation (2026-10-23)

Main's full Flutter suite passed (402 tests); after final persistence validation,
all 28 affected snapshot/local-data/overlay tests passed. Snapshot tests cover
restart, repeated category reads with zero HTTP requests, replacement, failed
persistence, rejecting partial initial data and preserving pending shopping edits.
The former offline-cache download is disabled in production. Completed versions
are stored in LocalData; older caches never satisfy the initial setup gate.

# Household meal planning (version 2 feature branch)

`codex/meal-planning-v2` is owned by the Plan CTR meal planning v2 chat. The
matching backend branch is in the canonical PHP repository. This work does not
change the release version, main branches, release tags or published app.

## Interaction

Open Meal planner from the existing navigation drawer. The scrolling date list
opens with today near the middle; Today returns there. Earlier dates have a
darker background; today uses an olive heading, badge and left border. Each date offers Add: Recipe
opens the existing recipe browser in selection mode; Leftovers and Restaurant
outing create matching placeholder tiles. The recipe browser stays beside the
date list on wide screens and supports dragging recipes into the plan.

Hold a tile to drag it to another date, or drop it on the toolbar trash can to remove it. Every add or move requires a date. Tapping the recipe opens its normal detail page. Today uses olive accents without past-date background shading.
Recipe-browser long press and the recipe detail page offer Add to meal plan.
These additions choose a recipe variation if needed, then a date from household today and the following six days, with Another date opening the calendar. The recipe action's View plan shortcut returns to the planner.

A recipe newly assigned to a date offers existing frequently paired recipes,
excluding recipes already there. This applies to additions from the browser and recipe viewer as well. Moving between dates never offers pairings. Suggested additions
do not recursively offer more suggestions. Placeholders have no ingredients,
recipe history or pairings.

Adding, removing, or moving into/out of a past date asks once before the change:
“Change this past meal? This will update your cooking history.” Cancel does not
write. API enforcement covers stale screens and midnight rollover too.

## Shared state and history

All members use the selected household's plan. The API supplies the household's
today and timezone, initially America/New_York, rather than deriving shared dates
from a traveling member's device timezone. Changing that default for an existing
household is a deliberate data change, not an automatic timezone guess.

Each operation compares the household revision. Calendar data is mirrored in
persistent local storage and ordinary operations commit to a durable local outbox.
Conflicts preserve the local edit for explicit review; no remote revision is
silently overwritten. Return/resume and the active planner's periodic refresh
read local data immediately while synchronization runs separately.

Planner readiness is discarded on an HTTP 401 (authentication interruption),
404 household_not_found (missing membership/household), or 403 account_disabled.
These meanings were checked against the backend authentication/bootstrap and
HouseholdService::membership paths. This clears in-memory entries/revision and
hides planner actions and its desktop recipe picker until an authorized refresh
succeeds. It does not sign out the user or delete household membership. Network
failures, 429/5xx responses and unrelated 404 errors retain useful cached meals.
Access invalidation also applies to a mounted hidden tab and prevents late reads
or pending planner confirmations/pickers from restoring or changing stale state.
Regression coverage includes denial on writes, expired authentication, recovery,
out-of-order reads, hidden-tab completion and transient failures. This source fix
does not rebuild localhost or deploy the app/backend.
Validated on 2026-10-23 with clean Flutter analysis and 29 passing focused access,
planner and navigation tests, including 14 new access-state regressions.

Dated recipe entries themselves are durable preparation history once their date
is before household today. No confirmation or daily job is needed. Correcting a
past entry corrects that history. Each occurrence keeps the recipe identity,
title and revision snapshot even if the recipe is later purged. The history API
also returns existing recorded cooking events and their deleted-recipe archives;
it does not duplicate those events during reads. Future recommendation features
can consume this API; recommendation screens are outside this implementation.

## Ingredients and shopping

Ingredients opens today and all future planned meals directly, then reuses
RecipeShoppingSelector and the same shopping-list write helper as recipe detail.
Each scheduled occurrence contributes once. Explicit amounts with the same
ingredient name, compatible unit spelling, preparation and optional status are
summed. Ambiguous text amounts, ranges and incompatible units remain separate;
no mass/volume or density conversion is guessed. Existing shopping duplicate
warnings and revision-safe additions are preserved. As in the existing recipe
flow, the shopping list receives selected ingredient names; quantities are shown
in the ingredient review. Unscheduled dishes and placeholders are excluded.
Unavailable scheduled recipes stop collection rather than silently omitting
their ingredients. Per-meal serving overrides are not introduced.

## Validation

Flutter analysis and the full 373-test regression suite passed during initial
implementation. Planner tests cover past cancellation/confirmation, placeholders,
dragging with pairing rules, recipe-picker reuse, conflicts and ingredient sums.
The backend adds membership, date/timezone, revision rollback, history rollover,
purge retention and repeated-occurrence ingredient fixtures. See the PHP
repository's docs/meal-planning.md for migration/deployment and hosted results.

## Localhost web build — 2026-10-23

At the user's request, built feature source `ceb333c5d268ae6a82918dd35e052df264b133e2`
with the existing ignored Firebase configuration and hosted coffeybean.com API.
Published the generated assets only to the local XAMPP app directory and verified
SHA-256 matches for served main.dart.js, flutter_bootstrap.js, version.json and
assets/FontManifest.json. Apache serves http://localhost/CoffeyTableRecipes/app/.
The existing 1.8.5+29 version label was retained; this is a feature-branch preview,
not a version 2 release. No hosted frontend, main branch or release tag changed.

## Android test APK — 2026-10-23

At the user's explicit test-build request, built exact feature source
`8009bf69ce3e9610e364544ac07a5c03258a275e` with `flutter build apk --debug`
and the existing ignored Firebase configuration, using the hosted backend.
Main's subsequent Kotlin and cache changes were not implicitly merged.

Saved `G:\My Drive\recipe app\CoffeyTableRecipes-meal-planning-v2-test-8009bf6.apk`
(174,693,850 bytes), retaining the separate existing release APK. Verified APK
Signature Scheme v2 with the Android Debug certificate, debuggable flag, package
`com.coffeytable.coffey_table_recipes`, version 1.8.5/code 29, minimum SDK 24,
target SDK 36 and arm64-v8a/armeabi-v7a/x86_64 architectures. Source and destination
SHA-256 both equal `a24c477548ba9045b5374dcbcb44cf88881270230ce9edffd733e7b87ef328f1`.
Generated APK/configuration remain excluded from Git. No device installation,
release, tag, hosted frontend/backend deployment or dependency change occurred.


## Planner interaction update (2026-10-23)
Date Add opens the existing browser with a persistent contrasting Add to [full date] line under its breadcrumbs. Every selection loads the current recipe family and opens confirmation: choose the original or an available household variation, then Add; Cancel leaves the picker open without a write. Normal browsing is unchanged. Recipe detail keeps full-width Start cooking, followed by equal-width Add to meal plan and Request variation buttons. Trash deletion retains past-history confirmation and access/revision guards.

Validation: flutter analyze --no-pub clean; full flutter test --no-pub suite passed (389 tests).


### Updated Android debug build (2026-10-23)
Built source `1595dc13e5cb85556bab4438d5eac6513fe24175` with `flutter build apk --debug --dart-define-from-file=config/firebase.local.json`. Saved `G:/My Drive/recipe app/CoffeyTableRecipes-meal-planning-v2-test-1595dc1.apk` (199,763,398 bytes). Source and delivered copy SHA-256: `8c687d2774db9d9764fad2674e9804bbb5ff5fe17ee3975ec6d0125050e96358`. APK v2 signature verifies with the existing Android Debug certificate (`f8de933f14b9bb4b3191a94aedc8637972c5ab224565f6abd7808f8038d12097`). Package `com.coffeytable.coffey_table_recipes`, version 1.8.5/build 29, debuggable, minimum SDK 24/target 36. No device installation, release tagging, main merge, or hosted Flutter deployment performed. Existing packages retained.


## Confirmation and feedback refinement (2026-10-23)
Recipe-view Add to meal plan uses the same confirmation/household-variation chooser as the dated picker, retaining Unscheduled as its destination. The picker destination label is larger and bold. The toolbar trash target is leftmost with a 104 by 80 logical-pixel hit area and full-area hover highlight. Dropping outside the visible icon still deletes; past dates retain confirmation.

Addition feedback and View plan expire after five seconds (including accessibility navigation mode), and are dismissed when navigating to another route or drawer section. A write finishing after navigation does not show stale success feedback. No backend changes are required.

Validation: full Flutter suite passed (397 tests); flutter analyze --no-pub clean. Regression coverage includes normal recipe confirmation/variation choice, enlarged off-icon trash drops, picker label styling, five-second expiry with accessibility navigation enabled, route push/pop and section cleanup, and late save completion after navigation.

### Android test APK after confirmation and feedback changes
Built source 1e77b0676de5638d63740f40823f259d1fdfb05a using flutter build apk --debug --dart-define-from-file=config/firebase.local.json. Saved G:/My Drive/recipe app/CoffeyTableRecipes-meal-planning-v2-test-1e77b06.apk (199,766,529 bytes). Source and delivered copy SHA-256: c3cd85f9961f1619e2554a3450bb6a0b1d7bf89853d6b65b5f50db83ec829b8c. APK v2 signature verifies using the existing Android Debug certificate f8de933f14b9bb4b3191a94aedc8637972c5ab224565f6abd7808f8038d12097; package com.coffeytable.coffey_table_recipes, version 1.8.5/build29, debuggable. No installation, release, main merge, backend or hosted Flutter deployment. Earlier test packages and the experiment branch were preserved.


## Ingredient review update (2026-10-23)
Removed the manual planner refresh icon; automatic refresh remains. Ingredients opens the existing shopping selector directly for today through all supported future planned dates (2199-12-31). Its title has a calendar button for an optional custom today/future range. Cancel preserves the list and checked ingredients; applying a range replaces the list and clears prior selections. Empty ranges still show the calendar action.

A broad plan read discovers all scheduled recipe dates, including dates outside the visible scrolling window. Ingredient requests group occupied dates into nonoverlapping spans of at most 366 days to respect the existing API limit. No backend change or database mutation is required. Amounts trim trailing zeroes; customary quantities use common mixed fractions with the existing recipe-import tolerance, while metric amounts retain decimals. Compatible quantities are summed before formatting; descriptive quantities, optional ingredients and incompatible units remain separate.

Validation: flutter analyze --no-pub clean; full flutter test --no-pub suite passed (401 tests). Coverage includes direct all-future opening, distant planned meals within API bounds, calendar cancellation, custom-list replacement and selection reset, customary fractions and trimmed metric amounts. Access regressions now use automatic resume refresh instead of the removed button.


### Android ingredient-review test APK (2026-10-23)
Built source `83f6d8b3cd62db1d999216f15992c5264076e6db` with `flutter build apk --debug --dart-define-from-file=config/firebase.local.json`. Delivered `G:/My Drive/recipe app/CoffeyTableRecipes-meal-planning-v2-test-83f6d8b.apk` (199,773,366 bytes). Source and delivered SHA-256 match: `5ca1c4871363a9d7910399f2adc97583429a314e16bfaa4a28a07a29ecff7a74`. APK v2 signature verifies with the existing Android Debug certificate (`f8de933f14b9bb4b3191a94aedc8637972c5ab224565f6abd7808f8038d12097`); package `com.coffeytable.coffey_table_recipes`, version 1.8.5/build29, debuggable. No device installation, release/tag, main merge or hosted Flutter deployment. Backend and experiment branch unchanged; earlier packages retained.


## Cooking fractions, drag scrolling and recipe creation (2026-10-23)
Customary ingredient totals round upward to the next standard eighth/quarter/half or third measure (1/8, 1/4, 1/3, 3/8, 1/2, 5/8, 2/3, 3/4, 7/8, whole), with a small tolerance for stored decimal noise. For example, 1.0833333 cup becomes 1 1/8 cup. Totals are combined before rounding; metric decimals remain unchanged.

Dragging near the top/bottom of the date list uses a continuous 30 ms timer and a wider edge zone with speed increasing near the edge. Pointer updates no longer restart the timer. Moving into the center pauses scrolling; release/cancel stops it. This applies to held plan tiles and the wide-screen recipe browser's drag callbacks.

Add recipe moved out of the household drawer to directly below the normal recipe browser search bar. It reuses the existing import flow and household identity. The subsequent local-first update allows blank recipes offline after the initial catalog download; AI imports still require a connection. Meal-plan selection browsers hide the action.

Validation: flutter analyze --no-pub clean; full Flutter suite passed (405 tests). New regressions cover continuous high-frequency drag updates, upward/downward scrolling and stopping, cocoa powder and other rounded customary quantities with unchanged metric values, Add recipe placement/callback/offline disabling and picker hiding.

## Local-first planner (2026-10-23)

The planner now shares the persistent local-data repository and durable outbox
with recipes and shopping lists. It mirrors the complete supported calendar,
reads date ranges locally, preserves a loaded view during synchronization, and
derives paired dishes/ingredients from household recipe data. Offline operations
survive restart; revision conflicts and server-required history confirmations are
retained for explicit review. Blank recipe creation remains available offline
after its initial catalog download. See [local-first-data.md](local-first-data.md).

Validation: full suite passed (433 tests); final affected suites passed (94 tests),
including a persisted planner displayed while the network never returns,
calendar add/move/remove across restart, household-filtered pairings, ingredient
collection, local/canonical recipe IDs, access-loss races and ingredient-only
remote changes. Static analysis clean. No app build or hosted deployment.


### Android cooking-measures and scrolling test APK (2026-10-23)
Built source `9f15da09a52a21f497a2e64e17dbc7c43dd603e6` using `flutter build apk --debug --dart-define-from-file=config/firebase.local.json`. Delivered `G:/My Drive/recipe app/CoffeyTableRecipes-meal-planning-v2-test-9f15da0.apk` (199,774,032 bytes). Source/delivery SHA-256 match: `cfe621826f7b86f914d3e004b549347776815509dfb2e83189287026473a588e`. APK v2 signing verifies with existing Android Debug certificate SHA-256 `f8de933f14b9bb4b3191a94aedc8637972c5ab224565f6abd7808f8038d12097`; package `com.coffeytable.coffey_table_recipes`, version 1.8.5/build29, debuggable. No device installation, release/tag, main merge, backend change or hosted Flutter deployment. Earlier packages and the separate experiment are preserved.


## Drag stop safety and toolbar zones (2026-10-23, no rebuild)
Meal-plan ingredient rows display the ingredient name and amount/unit only, omitting preparation, parenthetical/comma notes and optional-detail labels. Recipe-view shopping behavior remains unchanged.

The toolbar's entire left third is the trash target. Its right two-thirds trigger upward scrolling when the dragged tile reaches the toolbar or above; the date list itself no longer triggers upward scrolling. The bottom edge still scrolls toward future dates. Trash hover never scrolls.

The planner tracks the active drag pointer independently of the source tile. Pointer release/cancellation stops the timer even after the source leaves the viewport. App backgrounding, route changes, hiding the planner, access loss and disposal also stop scrolling; stale drag updates cannot restart it on an inactive screen. No app rebuild is part of this change; existing APKs do not include it.

Validation: flutter analyze --no-pub clean; full Flutter suite passed (411 tests). Regression coverage includes quantity-only details, exact toolbar trash-third sizing, no upward scrolling inside the date list, trash hover without scrolling, pointer release/cancellation after the source leaves the viewport, background/navigation/hide stops, and stale drag updates on inactive screens. No rebuild was performed.


## Main synchronization audit (2026-10-23)
Merged Flutter main `66cbb11e83743ebf8500fa6ffb58eea29b56cb08` into the feature branch, rather than relying on earlier individually copied changes. Restored all remaining main updates, including Kotlin 2.4.21 tooling/security notes, complete cached-first detail/public-link handling, account cached-request support, offline progress fixes and the previously missing communication/offline regressions. Shared LocalData, API and save-notification code/tests match main; retained the complete local planner, its first-use calendar requirement, all feature controls and the separate experiment branch.

Resolved overlap by preserving planner-specific navigation/readiness and adding main's shared cache behavior. Full Flutter suite passed (458 tests), static analysis clean, diff whitespace checks clean. Backend main `0dad2b1ef28682881bf206c493178064e3248124` was independently merged and verified on its feature branch. Both main heads are included as merge ancestors. No builds, schema changes or hosted deployments were requested or performed.


### Updated feature Android test APK after main integration (2026-10-23)
Built clean source `27dc7320f50fe3e5213516f764e2763438a12f46` with `flutter build apk --debug --no-pub --dart-define-from-file=config/firebase.local.json`. Delivered `G:/My Drive/recipe app/CoffeyTableRecipes-meal-planning-v2-test-27dc732.apk` (199,898,038 bytes). Source and delivered SHA-256 match: `ae6d3b511892b813e9efcf006637ac29e78a2f6cc8606367f35f8c336e47222f`. APK v2 signature verifies with existing Android Debug certificate SHA-256 `f8de933f14b9bb4b3191a94aedc8637972c5ab224565f6abd7808f8038d12097`. Package `com.coffeytable.coffey_table_recipes`, version 1.8.5/build29, debuggable, minimum SDK24/target36. Build succeeded with existing plugin compatibility warnings; last merged-source verification was 458 passing Flutter tests and clean analysis. No device installation, release/tag, web build, backend change or hosted deployment. Existing packages retained. This subsequent commit only records build verification.


## Accepted required-date planner (2026-10-23)
The user accepted and merged the no-Unscheduled experiment into this feature. The Unscheduled section and undated add routes are removed. Normal browser, regular/blank viewer and wide planner browser taps choose a variation if applicable, then a date; direct dated Add/drag retain the selected date. All new add/move operations require valid dates before durable queuing. No legacy migration was requested because no existing unscheduled meals need handling. Historical experiment/build records are in `meal-planning-no-unscheduled.md`; its separate branch was retired after accepted history was preserved and synchronized. No rebuild or deployment accompanied acceptance.

## Planner refinements and restaurants (2026-10-23)
Recipe tiles use the locally stored cover immediately when a meal is added, after following View plan, after restart and after synchronization. Upward drag scrolling begins only after a continuous 500 ms hover over the toolbar's right two-thirds (or above); entering the trash zone cancels the delay. Existing release/cancel/navigation/background stops remain in force.

Recently deleted is beside Add recipe below browser search, with both hidden during meal selection. Startup restores the last Recipes, Shopping list or Meal planner section for this device/account; Recipes opens at All Recipes. Section writes are ordered and preference failures never prevent navigation. Browser additions retain variation selection; recipe-view additions use the exact version currently open, followed by the date selector.

Household & people now contains Manage restaurants. Members can add, rename, remove and reorder their shared restaurant list. Restaurant outing selection lists configured restaurants followed by generic Restaurant. Saved outings retain the name selected at creation. Nullable logo references are reserved in configuration and saved entries; logo upload is future work. Changes use the existing local durable queue and household snapshot synchronization.

Validation: all 470 Flutter tests passed; static analysis and whitespace checks clean. New regressions cover immediate/restarted cover images, restaurant queue/name retention, restored sections, exact viewed version, restaurant selection/management, offline Add recipe and delayed scroll cancellation over trash.

### Verified local web and Android test builds (2026-10-23)
Built clean source bc90ae103bb3f7140b30d08f5d16d5770cef658a with `flutter build web --no-pub --base-href=/CoffeyTableRecipes/app/ --dart-define-from-file=config/firebase.local.json` and `flutter build apk --debug --no-pub --dart-define-from-file=config/firebase.local.json`. Prepared cache-safe web fonts/source metadata and copied to the ignored local PHP app directory. HTTP byte verification matched version.json, main.dart.js, flutter_bootstrap.js and FontManifest.json; local URL http://localhost/CoffeyTableRecipes/app/. Main JS SHA-256: e7c12bec1eec05185723185fedab820e1969f93e91b9fb43d6b5ee2ed0f84baa.

Delivered G:/My Drive/recipe app/CoffeyTableRecipes-meal-planning-v2-test-bc90ae1.apk (199,921,219 bytes). Build and delivered SHA-256 match: 4116ebc53fbe858f4cf35bec1acbcb8a9140b6abe98a3fcb93f6a34a7392804a. APK v2 signature verifies with Android Debug certificate SHA-256 f8de933f14b9bb4b3191a94aedc8637972c5ab224565f6abd7808f8038d12097; package com.coffeytable.coffey_table_recipes, 1.8.5/build29, debuggable, minimum SDK24/target36. Build passed with existing plugin/Kotlin compatibility warnings. No device installation, release/tag, main merge or hosted Flutter publication was performed. Backend restaurant rollout is recorded independently in the PHP repository.

## Accepted main merge and release handoff (2026-10-23)
User accepted the completed feature and explicitly requested merging and retiring its branch, followed by instructing Deployment to release version 2.0 on all platforms. Main was already an ancestor of feature tip f321bd39510e8e7c4aabcbbad36ad4adbac9a484. A non-squash merge preserves all accepted commits; the merged application tree exactly matches that tip, previously verified by 470 passing Flutter tests, clean analysis and verified local web/Android debug builds. Ownership is handed to Deployment for release preparation, changelog/version update, signed platform builds, hosted publication, native link verification and TestFlight processing checks. Existing release tags, private configuration and archive worktrees are preserved.

## Child mode, ingredient warnings and settings layout (2026-10-23)
Planner ingredient review now warns when selected meals include blank recipes, names each included blank recipe once, and updates the warning when dates change. Other ingredients remain available. Manage restaurants is a ListTile immediately below Shopping list departments, matching its padding, text and chevron control.

Child mode is off by default and belongs to the signed-in account. The user menu enables it after matching 4–8 digit PIN entries; disabling requires that PIN online. The backend keeps only a salted hash and throttles incorrect attempts. App controls and the durable local-write/API boundaries permit viewing and recipe favorites while blocking recipe creation/editing/deletion/attachment/variation, meal-plan changes, shopping changes, household/settings changes and cooking/timer controls. Protected screens also check policy when opened directly. The app restores this account's last confirmed device policy before browsing, retains it offline, and refreshes authoritative policy during account loading and the existing online minute poll. Cached /me data cannot switch child mode off.

Designated administrators have a Disable child mode section listing registered app users, with selection and confirmation. Recovery is pending until a newer verified Firebase login; refreshing an existing token does not clear it. That login clears the forgotten hash and updates device state. Backend policy storage and authorization details are recorded independently in the PHP repository; no schema migration was required.

Validation: full Flutter suite passed (477 tests), then final focused tests passed (23, including two added offline/API and reactive-policy regressions); analysis and whitespace checks clean. Backend deployment fixtures, 127 tooling tests, 21 signed-identity checks and isolated PIN/default/isolation/throttle/recovery/blank-warning tests passed. This work authorizes a local web build only; no native package, release tag or hosted Flutter publication.

### Verified local web build (2026-10-23)
Built source 88a8767d603c024621404797268b11961bd37948 with `flutter build web --no-pub --base-href=/CoffeyTableRecipes/app/ --dart-define-from-file=config/firebase.local.json`, then prepared cache-safe assets/source metadata and copied to the ignored local PHP app directory. HTTP byte checks matched version.json, main.dart.js, flutter_bootstrap.js and FontManifest.json at http://localhost/CoffeyTableRecipes/app/. Main JavaScript SHA-256: bff03ce3fdad59347eca567b240b32f5283292d27d508580c0f6ba9e28306d88. Version metadata remains2.0.0/build30 with the new source commit and demonstration channel. This is a local build; the immutable released tag and native packages are unchanged.

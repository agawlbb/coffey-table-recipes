# Household meal planning (version 2 feature branch)

`codex/meal-planning-v2` is owned by the Plan CTR meal planning v2 chat. The
matching backend branch is in the canonical PHP repository. This work does not
change the release version, main branches, release tags or published app.

## Interaction

Open Meal planner from the existing navigation drawer. The scrolling date list
opens with today near the middle; Today returns there. Earlier dates have a
darker background and today has the primary tint. Each date offers Add: Recipe
opens the existing recipe browser in selection mode; Leftovers and Restaurant
outing create matching placeholder tiles. The recipe browser stays beside the
date list on wide screens and supports dragging recipes into the plan.

Hold a tile to drag it to another date. Meal options offer Move to date,
Unscheduled and Remove; tapping the recipe opens its normal detail page.
Recipe-browser long press and the recipe detail page offer Add to meal plan.
These additions go into the household's Unscheduled section, visible only when
it has entries. The recipe action's View plan shortcut returns to the planner.

A recipe newly assigned to a date offers existing frequently paired recipes,
excluding recipes already there. This also applies when scheduling an
unscheduled dish. Moving between dates never offers pairings. Suggested additions
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

Each operation compares the household revision. Conflicting edits refresh the
screen and ask the user to review/retry, without silently replaying the write.
The planner refreshes on return/resume and every 30 seconds while active. Writes
require a connection; no offline mutation queue is introduced.

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

Ingredients opens a date-range picker for today/upcoming meals, then reuses
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

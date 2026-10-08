# Coffey Table Recipes — implementation checkpoints

## 1: Runnable foundation

- Flutter Android, iOS, and web project, provisional identifier `com.coffeytable.coffey_table_recipes`.
- Responsive meal-plan home shell with real API health status, loading/error states, and retry.
- PHP `/api/v1/health`; no household data endpoints until verified authentication exists.
- Database migration runner with checksums and an advisory lock.
- Initial users, households, memberships, and household people tables.
- Protected server configuration and storage directories; local secrets ignored.

## 2: Identity and household isolation

Register Firebase applications, Google sign-in, server-side ID-token verification, first-household setup, and tests proving cross-household access is rejected. Select dependencies compatible with the hosted PHP version before implementing authentication.

## 3: Recipe foundation

Add recipe families/variations, original-language content, rational quantities and original units, ingredient groups, steps/actions, media, classification, favorites, pairings, event history, nutrition provenance/revisions, and dated meal entries. Use composite household foreign keys to protect relationships. Seed 12 fictional development recipes after authentication and household provisioning exist.

## 4: First usable meal planning and cooking

Tonight's dinner, date-range planning, multiple dishes, add/move/remove entries, browsing and structured filters, recipe detail, and scrolling cooking steps.

Later: timers/scaling/conversion and offline synchronization; sharing/PDF; external automation; explicit reviewed AI workflows. Do not implement these before their checkpoints.

## Data conventions

- Server data is authoritative; client never connects to MySQL.
- Preserve original ingredient wording and exact quantities; conversion is for display.
- Household people may have no account; users may belong to multiple households.
- Recipe translations and culinary variations are separate concepts.
- Nutrition calculation records reference recipe revisions and become stale on relevant edits.
- Mutations will use optimistic revision checks; cooking history retains recipe revision references.
- UTC server timestamps; household-local calendar dates for meal planning.

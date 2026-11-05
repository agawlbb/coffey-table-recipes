# Meal-plan sync and recipe sharing repair

Task branch: `fix/meal-plan-sync-recipe-sharing`.
Base: `origin/main` at `9487cca5d4946551351a7f063a069e8d2bbe2731`.

A recipe receives a temporary `local-…` ID before its first upload. Routes and
previously selected recipe rows can retain that ID after the upload succeeds.
The repository resolved aliases in request paths, but not in new meal-plan
request bodies. Its upload queue then skipped those meal changes indefinitely
because they still referenced a temporary ID. The sharing actions also used the
route ID instead of the loaded recipe's server ID. Sending showed a misleading
connection error; copying HTML threw before the clipboard write.

The repair resolves recipe references before saving and before choosing a queued
upload. This also allows previously stuck queued edits to resume after restart.
Local plan reads resolve saved recipe references as well. Unresolved creations
still wait for their original upload; no replacement recipes are created and
revision conflicts continue to require review.

Sharing uses the loaded recipe's canonical ID. A recipe that has never synced
shows an accurate pending-sync message. The HTML-copy option was removed at the
user's request: the Share recipe button now opens device sharing directly, with
the existing plain-link copy fallback if platform sharing is unavailable.

The green cloud now requires both an open household connection and no pending
saves or repository errors for the active account. Pending/failed synchronization
shows an amber cloud with its status. The household screen now renders the
existing local-sync status and retry/review controls so interrupted or conflicting
saves are visible and recoverable.

Validation includes regression tests for adding a meal after a recipe's temporary
ID was already resolved, resuming an already queued edit after restart, sharing
from a retained temporary route on an iPad-sized iOS widget configuration,
unsynced-recipe feedback, platform-sharing fallback, and indicator transitions.
These tests verify app logic with simulated transports; they do not establish
that the reported iPad has received a fixed app or that its current local queue
has uploaded. No app build, deployment, or main integration is included.

Verified on 2026-11-05 with Flutter 3.47.8:

- Before the fix, the new local-ID upload/restart tests failed with a stuck queue.
- `flutter test --no-pub`: all 627 tests passed, including the new regressions.
- Changed Dart files were formatted; `git diff --check` passed.
- `flutter analyze --no-pub lib/src/local_data.dart lib/src/account_panel.dart lib/src/connection_indicator.dart lib/src/recipe_browser.dart test/local_data_test.dart test/recipe_sharing_test.dart test/connection_indicator_test.dart`: no issues found.

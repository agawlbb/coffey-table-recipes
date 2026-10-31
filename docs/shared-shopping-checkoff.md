# Shared shopping-list tap protection

Task branch: `fix/shared-shopping-checkoff`.
Base: `origin/main` at `39a318bd77336f6ce2ed770d1f4aff6d46bbfe7f`.
Keep this branch unmerged pending the user's instruction.

The backend's `ShoppingListService::save` locks the household row while saving.
`ShoppingListChanges::merge` applies changed fields by item ID, rather than row
position. Inspection of canonical backend source found no path that redirects a
checked-state change to an adjacent item. This is source inspection, not a live
two-device reproduction or proof that every backend failure is excluded.

The app groups checked items below unchecked items. A refresh from another
member can therefore put a different item where the user was about to tap.
After an already displayed list's items or departments change, editing pauses
for two seconds. This includes local changes, server confirmations that change
the display, and conflict recovery. Initial loading remains usable immediately.
Unchanged responses and revision-only changes do not restart the pause.
Checking, inline editing, adding, deleting checked items, and drag changes are
blocked; scrolling and refreshing remain available. A refresh response is also
ignored while a row is being held, matching the existing drag/edit protection.
No app build or deployment is part of this task.

Regression coverage simulates a remote check moving Eggs into Milk's former tap
position, verifies that the incoming tap cannot write, checks disabled editing
controls, verifies the two-second unlock, and confirms revision-only refreshes
do not postpone unlocking. Both local-first and direct-request modes are tested.
Existing consecutive and queued-drag tests now wait for the editing pause before
starting another change.

Validation in the shared development container (Flutter 3.47.8):

- `flutter test --no-pub test/shopping_list_test.dart test/shopping_list_drag_lifecycle_test.dart test/shopping_list_retry_test.dart test/shopping_list_sharing_test.dart`: 30 passed.
- `flutter test --no-pub test/shopping_list_cache_test.dart test/shopping_sync_request_test.dart test/child_mode_test.dart`: synchronization and child-mode cases passed; two cache cases initially failed. The hold test needed to wait for the new pause between drags. The offline test caught draft input being disabled while disconnected; the field now preserves the previous offline behavior outside the display pause. Cache tests were rerun separately after those corrections.
- Changed Dart files formatted and analyzed with no issues. The final correction only changes draft input availability while disconnected; connected-list checks remain applicable.
- All eight GitHub workflows use `workflow_dispatch`; publishing this source branch does not trigger app builds or deployment.
- Final `flutter test --no-pub test/shopping_list_cache_test.dart`: all 7 passed.

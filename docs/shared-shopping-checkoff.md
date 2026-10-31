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
When a refresh changes an already displayed list's items or departments, editing
pauses for two seconds. A conflict recovery also pauses if the fetched state
differs from the last confirmed state. Local edits, save acknowledgements
(including automatically assigned departments), and failed-save rollbacks do
not start a pause. Initial loading remains usable immediately. Unchanged
responses, revision-only changes, and refresh echoes of local saves do not
restart the pause.
Checking, inline editing, adding, deleting checked items, and drag changes are
blocked; scrolling and refreshing remain available. A refresh response is also
ignored while a row is being held, matching the existing drag/edit protection.
No app build or deployment is part of this task.

Regression coverage simulates a remote check moving Eggs into Milk's former tap
position, verifies that the incoming tap cannot write, checks disabled editing
controls, verifies the two-second unlock, and confirms revision-only refreshes
do not postpone unlocking. Both local-first and direct-request modes are tested.
The tests also immediately check and uncheck after a local save and its refresh
echo. Existing consecutive edits and queued drags run with their original timing.

Validation for the remote-only revision in the shared development container
(Flutter 3.47.8):

- `flutter test --no-pub test/shopping_list_test.dart test/shopping_list_drag_lifecycle_test.dart test/shopping_list_retry_test.dart test/shopping_list_sharing_test.dart test/shopping_list_cache_test.dart test/shopping_sync_request_test.dart test/child_mode_test.dart`: all 51 existing cases passed. The two new timing cases were corrected to allow single-tap recognition to finish and verified in the focused rerun below.
- `flutter test --no-pub test/shopping_list_test.dart`: all 10 passed, including both remote-only pause regressions.
- Changed Dart files formatted; `dart analyze lib/src/shopping_list.dart test/shopping_list_test.dart`.
- All eight GitHub workflows use `workflow_dispatch`; publishing this source branch does not trigger app builds or deployment.

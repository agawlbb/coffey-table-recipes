# Shared shopping-list tap protection

Task branch: `fix/shared-shopping-checkoff`.
Base: `origin/main` at `39a318bd77336f6ce2ed770d1f4aff6d46bbfe7f`.
Keep this branch unmerged pending the user's instruction.

The backend's `ShoppingListService::save` locks the household row while saving.
`ShoppingListChanges::merge` applies changed fields by item ID, rather than row
position. Inspection of canonical backend source found no path that redirects a
checked-state change to an adjacent item. This is source inspection, not a live
two-device reproduction or proof that every backend failure is excluded.

New checkoffs show their checked state immediately and remain in their current
department and position for five seconds before moving into the bottom checked
section. The five seconds start when the checkoff is first displayed on this
device, whether it was initiated here or received from another member. This is
presentation state only; saving the checked state does not wait. Each item has
its own timer. Unchanged refreshes and save acknowledgements do not restart it.
Unchecking or removing an item cancels its timer; rechecking starts a fresh five
seconds. Items already checked when opening the screen stay in the bottom list.
Timers are canceled when the screen closes.

A remote change can put a different item where the user was about to tap.
When a refresh changes an already displayed list's items or departments, editing
pauses for two seconds. A conflict recovery also pauses if the fetched state
differs from the last confirmed state. Local edits, save acknowledgements
(including automatically assigned departments), and failed-save rollbacks do
not start a pause. Initial loading remains usable immediately. Unchanged
responses, revision-only changes, and refresh echoes of local saves do not
restart the pause. The delayed move also pauses edits if the checkoff came
from another device. An active inline editor remains intact when that move
occurs, preserving entered text and matching the existing edit protection.
Checking, inline editing, adding, deleting checked items, and drag changes are
blocked; scrolling and refreshing remain available. A refresh response is also
ignored while a row is being held, matching the existing drag/edit protection.
No app build or deployment is part of this task.

Regression coverage tests remote-only edit pauses, local and remote five-second
moves in both local-first and direct-request modes, unchanged refreshes during
the grace period, cancellation and rechecking, department placement, and an
active inline edit surviving a delayed remote move. Existing consecutive edits
and queued drags retain their original timing.

Validation in the shared development container (Flutter 3.47.8):

- `flutter test --no-pub test/shopping_list_test.dart test/shopping_list_drag_lifecycle_test.dart test/shopping_list_retry_test.dart test/shopping_list_sharing_test.dart test/shopping_list_cache_test.dart test/shopping_sync_request_test.dart test/child_mode_test.dart`: all 43 cases outside `shopping_list_test.dart` passed. New timing assertions in that file were finalized and rerun below.
- `flutter test --no-pub test/shopping_list_test.dart`: all 16 passed, including local/remote delays, cancellation, remote-only pauses, and active-edit preservation.
- Changed Dart files formatted; `dart analyze lib/src/shopping_list.dart test/shopping_list_test.dart`.
- All eight GitHub workflows use `workflow_dispatch`; publishing this source branch does not trigger app builds or deployment.

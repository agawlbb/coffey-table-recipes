# Main dishes first in the meal planner

Temporary task branch: `fix/meal-planner-main-dishes-first`.
Base: `origin/main` at `8970194d722f5745db398559847b02aee9829a4a`.
User requested that this work remain unmerged pending approval.

Each date displays recipes assigned to Main Dish / Main dishes, including
subcategories, before other dishes. Existing relative order within both groups
is preserved. Classification uses existing household recipe detail requests;
there are no backend, database, or API changes. The plan paints before metadata
requests finish, so unavailable metadata does not prevent viewing cached meals.
Recipes without category metadata retain their order among other dishes.

Work is isolated in `build/main-dishes-first`; the existing
`feature/vps-remaining-php` test-build worktree is untouched. No app builds,
workflow dispatches, tags, deployment, or merge are part of this task.

Validation (2026-10-31):

- `dart format lib/src/meal_planner.dart test/meal_planner_test.dart`
- `flutter analyze --no-pub lib/src/meal_planner.dart test/meal_planner_test.dart`
- `flutter test --no-pub --concurrency=1 test/meal_planner_test.dart test/meal_planner_access_test.dart test/meal_planner_drag_stop_test.dart`

The new widget regression covers main categories, subcategories, stable order,
missing metadata, and isolation between dates. Existing checks cover cached-plan
rendering without network responses, access loss, responsive layout, and dragging.
Dependencies were initialized offline in this new worktree; the lockfile is unchanged.

Result: analysis reported no issues; all 44 focused tests passed. `git diff
--check` passed. All eight GitHub workflows use `workflow_dispatch` only;
source publication does not start a build.

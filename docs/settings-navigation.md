# Settings and person names

Task: menu reorganization and one person name, based on c75d8ee.

The hamburger menu keeps Recipes, Meal planner and Shopping list as primary
navigation. Settings opens over the current route, so Back preserves the recipe,
cooking screen or filters underneath. Its household section links to Household &
people, Shopping list departments and Manage restaurants. Supported native
platforms also show Cooking timers under This device. Administration is a separate
administrator-only drawer destination, unavailable in child mode.

The user dropdown contains identity, Change name, Child mode with its current
status, and Log out. There is no separate account display-name or table-name
control and no explanatory helper text. Your name remains a single free-form
field, allowing a first name, full name or familiar name without requiring a
surname or uniqueness.

The VPS account service owns the app name. Existing linked household names take
precedence over Firebase login metadata; opening the app does not bulk rename
existing people. Where historical linked names differ, the oldest linked person
supplies the account's displayed name until the user explicitly changes it.
POST /me/name updates the stored account and every linked household person in one
transaction. Unlinked people retain their existing names. Firebase remains the
credential provider; its login name cannot overwrite an app name. New household
setup uses Your name for both the account and the household person. Person IDs,
memberships, favorites and cooking history are preserved.

The matching VPS source is on task/settings-and-one-name. Publish that backend
change before distributing an app built from this branch; the app uses the new
account command. This source task does not authorize an app build or deployment.

Validation (2026-11-01):

- Changed Dart files formatted; affected app and test files analyzed with
  `flutter analyze --no-pub`.
- Focused widget runs covered home/name editing and failure handling, logout,
  narrow and wide layouts, account menu, timers, role/child visibility, navigation
  from browser/detail/cooking, shopping departments, and child-mode restrictions.
- The backend branch passed account/data fixtures and 9 real local account
  WebSocket tests; see its SETTINGS-NAMES.md for commands and scope.
- No app build, hosted publication, main merge or production-data test was run.
- Full `flutter test --no-pub`: 563 passed, one obsolete assertion still expected
  Administration in the user dropdown. Updated that test to use the drawer;
  `flutter test --no-pub test/administration_test.dart` then passed all 9 tests.
  All other full-run results were retained; the full suite was not repeated.
- Final affected-file analysis (including administration tests): no issues found.

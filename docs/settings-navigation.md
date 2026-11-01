# Settings, full names and household display names

The task branch resumes the original settings reorganization at app ffc2fa9 and
VPS backend b303c59. The revised behavior keeps account and household identities
independent; no schema migration or bulk rename is needed.

The account bubble shows Full name, Child mode with its current status, and
Log out. Full name edits the account-wide users.display_name, which is used for
account identification, invitations and administration. Firebase remains the
credential provider; a stale login name cannot overwrite the stored full name.
The sign-up name field is also labeled Full name.

Settings uses a bold, slightly larger household heading. Household members,
Shopping list departments and Manage restaurants share one indentation beneath
that heading. This device and Cooking timers remain outside the household group.
There is no full-name control in Settings and no explanatory helper text.

Household members shows an edit icon beside an adult's own name. Household owners
and admins also see an edit icon beside linked child accounts. The dialog field
is Display name. An edit updates only that household_people row, leaving the
account full name and names in other households unchanged. Children cannot edit
either name. Unlinked people and other adults have no name-editing icon.
Favorites, meal planning and household member lists retain household display
names. Existing names, person IDs, favorites, memberships and history are retained.

The matching VPS task branch adds the account-scope
POST /households/{household}/people/{person}/name command with server-side
membership, role and child-mode checks. POST /me/name changes the full name only.
The existing own-person name route also stays household-scoped and rejects child
callers. Publish the revised backend before distributing an app built from this
revision. The earlier test APK remains the previous single-name implementation.

Settings opens over the current route, so Back preserves the recipe, cooking
screen or filters underneath. Administration remains a separate administrator-only
drawer entry. No app build, main merge or runtime deployment is part of this
source revision.

Validation (2026-11-01):

- Changed Dart files formatted. Affected app/test files analyzed with
  `flutter analyze --no-pub`: no issues.
- One focused `flutter test --no-pub` invocation passed 83 tests across
  `home_design_test.dart`, `account_timer_menu_test.dart`,
  `administration_test.dart`, `recipe_menu_navigation_test.dart`,
  `shopping_departments_test.dart`, `backend_socket_test.dart`,
  `shopping_socket_test.dart`, `api_test.dart`, `recipe_filter_dialog_test.dart`,
  `recipe_favorites_test.dart`, `child_mode_test.dart`, and `email_access_test.dart`.
  New cases cover independent full/display name saves, failed display saves,
  owner/admin/member/child edit controls and the new account-socket route.
- Backend fixtures verify multi-household isolation, child and role restrictions,
  full-name preservation, legacy route protection and failed writes; 10 local
  account WebSocket tests pass. See the backend SETTINGS-NAMES.md.
- Checks are bounded to account/member name handling and its callers. No complete
  Flutter suite, installable app build or live-data edit was run for this revision.

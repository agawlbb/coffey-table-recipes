# VPS data transport

Task branch: `backend_migration`, based on fetched `origin/main` `882e392`.
The matching branches start at InMotion `5424e9d` and VPS `eb49ad5`.

The existing shopping WebSocket at `wss://ctr.coffeybean.com/shopping` now carries
recipe reads/adds/edits, favorites, deletion/restoration, shared-recipe attachment,
household snapshots, restaurants and meal plans. LocalData still owns local reads
and the durable outbox. Existing save IDs, revision checks and replay receipts
remain unchanged. Queued data sends depend on the VPS connection rather than
InMotion HTTP availability. Every new meal-plan add or move requires a date.

Household connections use the existing authentication, durable snapshot
installation, heartbeats, token renewal, network recovery and resume behavior.
The existing green cloud icon appears throughout the household app only after
both shopping and library snapshots have been saved. The shared manual sync/status
row and overdue-save notifications are no longer used for these automatically
synchronized data. No new labels, controls or screens are added.

Timers use account-scoped connections, immediate snapshots and existing durable
operation IDs. Existing native opt-in, account/device guards and mobile push
notifications remain. Foreground updates use WebSocket snapshots; reconnect and
existing reconciliation recover missed updates. An FCM acceptance still does not
prove that a suspended device scheduled an alarm.

The SQL database remains on InMotion. Signup/account provisioning, invitations,
account administration, child-mode PIN state and AI access remain there. Blank
recipe saves call the authenticated InMotion AI categorization endpoint without
moving its credential. New uploaded photos persist on the VPS; old InMotion
photo URLs stay valid, including in shared recipe pages.

Deployment stays in the VPS repository's existing `deploy.py`: copy code and
restart the service, preserving private configuration, state and photos. The
InMotion branch removes the migrated data handlers. Use the existing backend
publication process when publishing these matching branches. No compatibility
switch, staged cutover, schema migration or new deployment system is introduced.
Home Assistant already uses the shopping protocol and requires no source change.

No app build, release, installation or hosted-app deployment is authorized by
this source migration. These task branches remain available for review.

## Verification — 2026-10-29

- `flutter test --no-pub --concurrency=1`: all 544 tests passed. The earlier
  two-worker attempt exceeded the shared container's memory limit and was stopped;
  it was not counted as a completed suite.
- After the bounded timer account-switch and account-policy badge follow-up,
  `flutter test --no-pub --concurrency=1 test/backend_socket_test.dart test/timer_sync_test.dart test/shopping_socket_test.dart test/shopping_reconnect_test.dart test/local_data_test.dart test/snapshot_database_test.dart test/account_timer_menu_test.dart test/child_mode_test.dart`:
  all 85 tests passed. This includes the new regression rejecting old-account
  snapshots during unregister and after an account switch. The full suite was
  not repeated for this bounded follow-up.
- Changed Dart files and tests were formatted; affected-file analysis and
  `git diff --check` passed.
- Companion repositories verified disposable-SQL recipe add/edit/replay and
  meal/timer isolation, six real WebSocket tests (including the existing HA
  client), persistent photo serving with browser CORS, token renewal, three
  deployment-preservation tests and InMotion route retirement/account policy.

Child-account badges still come from the existing InMotion account-policy
response, containing only membership-scoped booleans. The app caches those flags;
PIN state and signup credentials are not transferred. Household names and people
changes use the same VPS connection as recipes and plans.

The existing VPS timer sender was provisioned privately for the data service with
mode 600 and its project checked against the existing Firebase configuration.
No backend service was restarted; no production data was used in tests. No app
packages were built, installed or deployed. The source branches remain unmerged.

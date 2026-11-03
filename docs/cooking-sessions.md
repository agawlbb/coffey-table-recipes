# Cooking sessions

Task: `task/cooking-sessions`. App base `0f3b822`; VPS base `c28b633`.

Starting cooking creates a server session and joins this installation. If the
recipe has an active session, choose the existing attempt or start another.
Starting a new session requires sign-in and a connection. Session progress uses
the recipe snapshot captured at creation, so later recipe edits do not change
step/action identities during cooking.

The household navigation drawer, including recipe detail and cooking mode, lists
recipe names with only **Open** (joined here) or **Join**. Both open the first
unchecked step; subsequent remote edits preserve the viewing position. Switching
dishes keeps other joined sessions and their timers active. Long-press goes
directly to household members; tapping one shares and sends an invitation. Access
is explicit, not automatically granted to the whole household. Invited sessions
remain in the recipient's drawer until ending/expiry, even after dismissing the
notification or initial mirror invitation.

Cooking has **End cooking session** at the bottom. Ending affects all participants
and cancels session timers; running timers require confirmation. Completing the
checklist or leaving the page does not end the session. The server starts the idle
period once no joined device is viewing that session in the foreground. It lasts
one hour plus the recipe's total estimate (or prep + cook when total is absent),
with a one-hour fallback. Reopening resets it; expiry cannot precede the latest
running timer's deadline. Foreground presence renews every 20 seconds with a
60-second server lease for unexpected disconnects. A lost connection can therefore
add up to a minute of grace. Expired sessions are removed on the next server sweep
or read; a 30-second sweep publishes expiry to connected clients. Recent ended
sessions retain cancellation tombstones for seven days.

## Transport and alarms

The existing authenticated WebSocket gains a `cooking` scope and
`/me/cooking-sessions` endpoints. Server-owned per-step and per-timer revisions
reject stale edits; operation IDs make retries idempotent. Different step edits
merge independently. Snapshots reconcile reconnects and app resume. Account
changes clear client session state immediately and reject delayed responses.
Household membership is rechecked for discovery, sharing and mutations.

Timers have session-scoped IDs and absolute deadlines. Native alarm state survives
app suspension; server time offsets adjust local countdowns/scheduling. Local
mobile start/edit/cancel operations are durably queued per account, preserving
deadlines, operation IDs and expected revisions. Steps require a connection;
failed edits remain unchecked/unchanged and report an actionable error.

Initial timer delivery and progress use WebSockets. Silent pushes supplement
cancellations and changes to existing timers for joined mobile devices. They
produce no timer-sharing banners or sounds. Background delivery is best effort:
an offline, suspended or force-stopped device can miss a cancellation and ring.
Visible invitation notifications are separate. Native account, installation,
session-membership and revision guards reject unrelated or stale timer updates.
The old account-wide receiving switch and Flutter timer-sharing coordinator are
removed. Existing server timer-device registration supplies push tokens; no new
credential or database setup is required.

## Server storage

The VPS stores sessions under the existing persistent `CTR_STORAGE/cooking`
directory. One locked JSON store is replaced atomically; the lock is separate
from the replaced file. The existing one-worker server owns broadcasts. Session
snapshots are filtered per authenticated user, and cooking recipe snapshots omit
private source text and editor-only metadata. WebSocket responses/broadcasts are
sent before the best-effort push sender runs. No schema migration or new service
is introduced. Existing deployment preserves the state directory.

## Validation

No app build,
release, native installation or main integration is part of this task. Native
background behavior and OS delivery still require physical-device acceptance in
an explicitly authorized build/release.

App verification on 2026-11-03:

- Changed Dart files were formatted; `flutter analyze --no-pub` passed for the
  complete project.
- `flutter test --no-pub --concurrency=1 --reporter expanded`: all **593 tests**
  passed. An earlier full-suite attempt lost its compiler under shared-container
  memory pressure while another worktree was testing; that interrupted attempt
  is not counted as passing.
- A bounded follow-up keeps screen-awake ownership with the visible cooking
  route, prevents duplicate route closure, and refreshes mobile push registration
  on resume. After that change,
  `flutter analyze --no-pub lib/src/cooking_mode.dart lib/src/cooking_sessions.dart test/cooking_sessions_test.dart`
  passed, followed by
  `flutter test --no-pub --concurrency=1 --reporter expanded test/cooking_sessions_test.dart test/cooking_mode_test.dart test/timer_sync_test.dart test/recipe_menu_navigation_test.dart`:
  all **23 tests** passed. The full suite was not repeated for this bounded
  follow-up.
- Coverage includes direct member selection from long-press, Open/Join navigation,
  switching/reopening sessions, first-unchecked positioning, stable scroll during
  remote changes, end confirmation, offline timer replay with unchanged deadlines,
  stable operation IDs and old-account response rejection. The existing backend
  socket test now also verifies the separate cooking scope and snapshots.
- `git diff --check` passed. Android/iOS native changes were reviewed but were
  **not compiled or exercised on devices**, because no app build was requested.

The companion VPS task branch has passed PHP and real WebSocket checks, including
periodic expiry without a client write. Backend implementation `27705ed` is
hosted; its deployment evidence is recorded in VPS commit `2d54351`. Public
configuration returned HTTP 200 and the cooking socket rejected an invalid token
with status 401. No production sessions or notifications were created for testing.
Both source branches remain separate from main. The app still needs an explicitly
authorized build/release and physical-device background alarm acceptance.

## Timer-range integration — 2026-11-03

Merged `task/timer-ranges` into `task/cooking-sessions`: app source `4c4f2bb`
and companion backend source `b6f8c1d`. Both task histories are preserved; main
is unchanged. The retired account-wide Flutter timer coordinator stays removed.

Range timers still start at the minimum and offer the remainder once. Session
snapshots, durable local timer operations and silent native updates now preserve
`extension_seconds`; extension operations carry their consumption flag through
the session endpoint. Server revisions and operation IDs prevent two devices
from consuming the same remainder. Manual timer changes/cancellation clear the
remainder. Native session/account guards and server-clock adjustment are retained.
Expired unused ranges can be restored without replaying an alarm. Web cooking
uses the same session extension rules.

This integration changes source only. It does not run database maintenance,
build packages, deploy either app/backend, or integrate into main. Earlier hosted
publication records above describe their respective source revisions.

Changed Dart files were formatted, complete-project `flutter analyze --no-pub`
passed, and the following command passed all **114 tests**:

```sh
flutter test --no-pub --concurrency=1 --reporter expanded test/recipe_time_test.dart test/timer_sync_test.dart test/recipe_import_test.dart test/recipe_chat_test.dart test/recipe_variation_test.dart test/recipe_editor_test.dart test/timer_visibility_preview_test.dart test/cooking_mode_test.dart test/recipe_timer_navigation_test.dart test/sharing_timers_test.dart test/cooking_sessions_test.dart test/recipe_menu_navigation_test.dart test/backend_socket_test.dart test/account_timer_menu_test.dart
```

The new session regression verifies range metadata survives offline queuing and
restart, and that extending clears it. Companion fixtures verify replay and
competing-extension rejection. The merge affects bounded timer, recipe import/
editor and session paths; the earlier full Flutter suite was not repeated.
Native source was reviewed; no native build or physical-device test was run.

## Signed Android test APK — 2026-11-03

The user explicitly requested deployment of the merged backend if needed and a
test Android APK. Backend implementation `4d2f1f0` was required and deployed; all
68 checked hosted source/bin/association/entry/lock files matched. Read-only
health and invalid-authentication probes passed. Deployment verification is
recorded in backend task commit `96ba5df`.

[Android test workflow](https://github.com/agawlbb/coffey-table-recipes/actions/runs/41558069132) succeeded on exact app source
`4ba9b88ec2de9d476f1d35b6db1688677ff18503`. Existing test-build mode produced package
`com.coffeytable.coffey_table_recipes`, version `2.6.0-account-test`, build **53**.
Android release/native compilation, original signing identity, non-debuggable
status, required timer-preference JNI classes and hosted app links passed CI.
Independent local `apksigner`, `aapt`, checksum and actual-certificate app-link
checks also passed.

- Delivered filename: `CoffeyTableRecipes-2.6.0-cooking-sessions-test-build53.apk`.
- APK SHA-256: `ba0586034122942d46d3edab7c360046f93e4f1921bfc9912de8354f88942946`.
- Certificate SHA-256: `f8de933f14b9bb4b3191a94aedc8637972c5ab224565f6abd7808f8038d12097`.
- [Verified Drive test APK](https://drive.google.com/file/d/1sEgy2EKjNnVDmDn6S79UrXiGVg6H0MIO/view). Uploaded bytes were downloaded and
  their SHA-256 matched. All existing Drive packages were retained; no release
  announcement was sent and sharing settings were unchanged.

The usual private recipe-app folder was used; no APK or update metadata was
publicly hosted on the VPS. No release tag, main integration, iOS/web build or
hosted Flutter deployment was performed. The source version was not changed;
the workflow supplied the test version/build override. Physical-device and
multi-device background alarm behavior remain for testing with this APK.

## Silent communication failures (2026-11-03)

Task `fix/cooking-sync-status` starts at canonical main `ce1b527`.
The cooking-session introduction (`af2965c`) routed background coordinator errors
into the account panel's global snackbar listener. Socket disconnects therefore
produced a startup notification, and cooking actions could display the same
transport error. Temporary communication failures now bypass the user-facing
error state and cooking snackbar helper. Existing household connection indicators
remain unchanged; validation and local alarm errors remain visible. Timer-device
registration failure no longer prevents the initial cooking-session refresh.

The repeated device disconnect itself has not been reproduced or explained.
Deployed server.php and DataSocket.php hashes match the backend checkout, and
available backend logs contain lifecycle events without a corresponding failure.
This change must not be described as a confirmed repair of the disconnect cause.

Validation: the six-file focused run passed 45 tests and failed the prior snackbar
expectation in the failed-session-end test. After updating that expectation and
adding registration-failure coverage, the affected timer_sync_test.dart and
cooking_sessions_test.dart suites passed all 27 tests. The other 20 focused tests
(cooking_mode_test.dart, account_timer_menu_test.dart, shopping_socket_test.dart,
backend_socket_test.dart) passed in the initial run. Changed Dart files were
formatted; scoped analysis and diff whitespace review passed. No build, release,
backend change or deployment was performed.

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

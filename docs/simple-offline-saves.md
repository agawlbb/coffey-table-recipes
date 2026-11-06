# Simple server updates and the agreed offline exceptions

Implemented on task branches from app `fe8f641` and backend `d122df5`.
No merge, deployment or app release is included in this implementation request.

The server accepts saves without comparing a submitted edit version to its own.
The last submitted save overwrites current data. Recipe rows removed by another
save can be recreated from the later editor submission. The same rule applies
to shopping, restaurant lists, meal-plan operations, cooking steps and timers.
Existing authorization, valid input requirements and actual timer behavior remain.
Database counters still used by history, timer delivery and existing wire formats
are not edit preconditions. Request/operation IDs identify repeat delivery;
they do not select which user's edit wins.

The foreground app still uses one shared connection. Initial/reconnected state
comes from the server and later changes arrive as pushes. The read cache now has
no general edit outbox, conflict states, rebase logic, confirmation comparison or
periodic data polling. The obsolete one-minute pending-save reminder and its settings toggle are removed. Shopping and meal planning no longer poll their screens.
Socket keepalive, automatic reconnection and existing cooking presence remain.
A snapshot application failure leaves readiness and reconnects through the same
transport. Damaged read-cache JSON is logged and replaced by fresh server state.

Offline work is stored separately for the signed-in account and backend:

- Removing checked shopping items records only those particular item IDs. The
  removals retry on reconnect and, while connected, after a failed attempt. They
  expire two hours after the removal, including across restarts. Expired actions
  are dropped and the server's list is displayed. A new item with the same name
  has a different ID and survives an older removal. Checking items while offline
  prepares them for Remove checked off; whole-list edits do not queue.
- New recipes saved offline are retained and automatically uploaded on reconnect.
  A retained save reuses its request ID if a success response was lost.
- Existing recipe edits saved offline stay separate from server data. After
  reconnecting, the screen identifies the recipe and offers Save to server or
  Discard my changes. Saving explicitly replaces the server recipe; discarding
  removes only the retained edit. Neither decision holds the socket or incoming
  updates. Other automatic work continues independently.

Before add/edit/shopping opens, a disconnected user receives a short message
based on known network availability and the applicable offline behavior. Save
messages distinguish locally retained work from server success. Failed uploads
are logged and reported, without changing connection readiness for pending work.
Only actual errors are retained in Error log; informational startup, lifecycle,
connection and sync-state entries are ignored and older informational rows are
filtered out. Error entries retain safe codes and app version, without payloads,
credentials or private exception messages. Copy to clipboard remains.

Tests of rejected version conflicts, whole-list retry queues and confirmation
holds have been removed or rewritten to assert these requested rules. Transport,
authorization, cache integrity, UI interaction and actual Dart/PHP connection
coverage are retained. Validation:

- Final analysis is clean. The full app suite completed with 598 passes, one
  optional integration skip, and six old assertions expecting versions/polling.
  Those six assertions were rewritten for push-triggered access changes and
  version-free saves; the affected tests pass in the subsequent focused run.
- 73 focused editor/chat/access/decision checks passed after the final behavior
  changes. Eleven additional offline-save, exact-expiration, storage-failure,
  shopping-screen and connection-recovery checks passed. Thirty final cache,
  notification-settings, actual connection/decision and failure-recovery checks
  passed after removal of the obsolete reminder setting.
- The real Dart/PHP shared-connection integration test passed with
  CTR_BACKEND_SOURCE pointing to the matching backend task branch.
- Backend fixture/protocol evidence is recorded in SIMPLE-SAVES.md in that repo.
  The optional external HA-client test could not start: automatic command review
  timed out twice, and the unprivileged fallback cannot access Docker. The
  shopping protocol fixtures and retained HA request acknowledgment were tested.
- No native packages were built. Physical affected-device acceptance and any
  merge/deployment/release remain outside this implementation request.

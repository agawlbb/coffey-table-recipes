# Local SQLite and live sync

Implemented on `feature/simple-offline-saves` with backend changes on
`feature/last-update-wins`. This work does not change the release version.

## Behavior

- Screens use local working data. Normal saves commit to SQLite and update the
  screen without waiting for a server response, including meal-plan moves.
- One existing foreground app connection receives server changes and sends local
  changes. The server applies submitted changes in arrival order; no edit-version
  comparison, conflict/rebase protocol, or whole-account confirmation gate.
- New offline recipes send automatically. Existing offline recipe edits and
  offline meal-plan changes remain visible locally and ask whether to save to the
  server or discard when connected. These decisions do not block other sync.
- Meal-plan changes address individual meals, not a replacement calendar.
- Shopping removals address item IDs and retry for at most two hours from the
  original removal, including across restart. At expiry the server list applies.
  Other ordinary local changes have no added expiry or decision screen.
- Existing shared-recipe edit and past-meal confirmations remain. Their redesign
  is deferred; they do not hold unrelated synchronization.
- The green icon represents the open healthy backend connection, independently
  of unsent changes or decisions. Errors remain available in the existing log
  with its copy option; normal sync activity is not logged as errors.

## Storage and delivery

SQLite stores account-scoped resource documents and pending changes in the
`resources` and `changes` tables. Each local save commits both atomically. The
working view combines received server data with still-unsent local changes, so
incoming data cannot hide a retained local edit. Discard exposes the latest
received server data. Existing file storage and offline actions are imported on
first use; this update does not clear local storage.

IDs associate a local creation with the server-created recipe or photo and prevent
repeated delivery from creating duplicates. They are not edit versions. Shopping
removal expiry and cooking alarm deadlines use time for those specific behaviors,
not for deciding which edit wins.

Delivery is independent per recipe, meal, or other resource. An unanswered or
failed save does not stop other resources or close the shared connection. The
existing heartbeat handles actual connection loss, and reconnect resumes pending
delivery. Pending work retries while connected; there is no idle library downloader
or periodic full-library verification. The VPS sends updated snapshots before
acknowledging writes. Account access, real input validation, and native alarm
permissions remain in force.

## Focused validation

Checks run in the development Docker container, without an app build or full test
suite. SQLite cases cover local visibility, restart, existing-data import, recipe
and meal decisions, shopping expiry, cooking progress, and attachment delivery.
Real WebSocket cases cover continued bidirectional sync with pending decisions,
a failed unrelated write, and an unanswered unrelated write after its timeout.
Account UI cases cover discard, submit, and the existing shared-edit confirmation.
The existing Dart/PHP integration checks the single authenticated connection.
Cooking and timer checks cover native action delivery and local restart behavior.
Backend fixture checks cover meal operations, data socket writes, and shopping
patches preserving unrelated server items.

These are isolated development checks. Native iPad/iPhone acceptance, production
deployment, app builds, and release distribution are separate and have not been
performed for this change.

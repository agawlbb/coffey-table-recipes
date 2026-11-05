# Client sync recovery and diagnostics

Follow-up to the 2.7.4 audit, 5 November 2026. The user reported an iPad that
still would not sync or become green, and intermittent iPhone synchronization.
These are reproduced client defects; without an affected-device log we cannot
establish which path each particular device encountered.

## Reproduced defects

1. The account header invalidated local confirmation on every notification from
   a socket that was not yet connected. Initial snapshot application persists
   and confirms data *before* the socket becomes connected. Its own notifications
   therefore revoked that confirmation. Green could depend on a later redundant
   snapshot request succeeding. Confirmation is now revoked by an explicit
   disconnect callback, not by observing the initial handshake in progress.
   The connected/applying/confirmed gates on green remain in place.
2. A startup storage-read failure was memoized in `_ready`. Every subsequent
   read and reconnect reused that failed future forever. Failed loads now reset
   the future for retry; a read that does not finish within ten seconds fails
   rather than blocking all future attempts. Saves still require a successful
   load, and durable writes remain serialized without a timeout.
3. The previous in-process replay logic did not cover restart. On restoration,
   interrupted meal-plan/restaurant/favorite operations could be marked as
   requiring review and then never retried. Restoration now uses the same
   replay-safety rules as the active queue. Only recognized old interruption
   holds without a real conflict code are cleared for safe recovery. Canonical
   meal/restaurant checks and recipe/shopping receipt identifiers are retained.
   Actual conflicts and non-receipted uncertain creates remain protected.

“Manual review” describes an internal blocked-save state. The existing main
screen pending-change banner has a Review button for queued conflicts; it does
not represent the confirmation or failed-startup-read bugs. No new conflict UI
or data-discard action is introduced by this repair.

A new account-coordinator test uses real WebSocket transport, platform storage,
and the actual account header, with the redundant snapshot read held back.
It verifies initial green, a remote recipe appearing, loss of green on disconnect
and autonomous recovery. Restored-queue tests verify lost acknowledgments and
preservation of genuine conflicts. Running these tests with the released
confirmation/read/restore behavior produces five failures. The corrected behavior
passes the eleven focused coordination, restart and logging tests.

## Device log

Settings → Error log opens the only new menu item. The viewer has selectable
text and a Copy to clipboard action. No automatic upload, extra alerts, badges,
review screens or changes to the normal navigation are added.

The log is device-local, survives app restarts, and keeps at most 300 events or
128 KiB. It records UTC timestamps, installed version/platform, safe error types,
source locations, API/Firebase/native status/code and route templates, disconnect/reconnect
attempts, pending-write counts, persisted snapshots, and the reason confirmation
is waiting. Framework and uncaught-platform hooks preserve existing handlers.
Transport errors are logged in their original type but requests receive the
retryable API error category rather than getting stuck as unknown exceptions.

Tokens, headers, URL query strings, actual route IDs, request/response bodies,
recipe content, personal names and arbitrary exception messages are omitted.
Logging storage is separate from recipe/outbox storage. Failure to persist the
log does not block synchronization; its current in-memory contents stay viewable.
Log history begins with installation of a build containing this change: it cannot
recover diagnostics from earlier installed versions. Recording the final event
before a process is forcibly killed is best effort.

## Validation

- `flutter analyze --no-pub`: no issues.
- Focused tests: coordination, restart recovery and log persistence/privacy/
  clipboard/handler behavior; eleven passed before the final full-suite run.
- Released-behavior comparison: five reproduced failures, including the actual
  account-screen handshake and four startup/restart cases.
- Full suite with `CTR_BACKEND_SOURCE` pointing to the production PHP checkout:
  **662 passed**, including the real Dart/PHP contract check; no hosted household
  writes. Afterward, safe Firebase/native error-code extraction was added to the
  logger and verified with **16 final targeted logging/recovery/settings checks**.
  Final analysis also reports no issues.
- Backend read-only inspection found no recent server errors, low resource use,
  and a running service. No backend change or deployment is part of this repair.

The new client code requires a new app build before it can run on the affected
phones/tablets. Physical-device multi-device acceptance remains unverified here.

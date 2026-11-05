# Data synchronization audit — 5 November 2026

Status: backend repair deployed and verified; client changes merged into main
and released as 2.7.4/build 59 to Android Drive and the existing TestFlight group.
Install build 59 for client corrections. See [delivery evidence](releases.md).

## Findings and corrections

| Area | Defect | Correction |
| --- | --- | --- |
| Shared links | Public WebSocket ready payload serialized as `[]`; Dart required an object and repeatedly disconnected. | Server emits an object; client also accepts the legacy empty public payload. |
| Unexpected responses | Parsing could remove a pending request before throwing, leaving it waiting for timeout. | Validate first; fail pending work and reconnect on invalid messages. |
| Silent/half-open transport | A timed-out request could leave a nominally connected socket. | Timeout retires the transport and starts existing bounded reconnect backoff. |
| Request errors | Missing recipes and ordinary permission errors closed the whole socket. | Keep these request failures scoped; disconnect on authentication/access revocation. |
| Token/lifecycle | Same-account token refresh and temporary inactive UI could interrupt writes. | Reuse same-identity sockets; reconnect after actual background/resume. |
| Screen recovery | An error screen could remain after transport recovery; optional cache I/O could hang a public read. | Retry after readiness and periodically on transient failures; bound optional public-cache access. |
| Offline state | Unrelated private offline state could suppress anonymous public reads. | Public reads attempt their own connection independently. |
| Saved data | Concurrent file writes shared a temporary filename. | Unique same-directory staging files with atomic rename. |
| Interrupted acknowledgments | Already-applied meal/restaurant operations and receipt-backed saves could become stuck. | Compare intended effect with canonical server data; replay receipts; retain genuine conflicts for review. |
| Stale replicas | Alias exemptions retained remotely deleted recipes; delayed partial reads could overwrite a full snapshot. | Replace clean canonical entries, including aliases; check household snapshot generation. |
| Green indicator | Connection state and empty queues did not establish persisted equality. | Require successful durable full snapshot, matching shopping baseline, no queue/errors, no active writes, and confirmed account/cooking state. |
| Metadata | Household name/role and user display metadata were absent from snapshot generation. | Include actor-scoped metadata in snapshot hash and broadcast successful account mutations. |
| Diagnostics | Unexpected backend errors lacked useful safe diagnostics. | Record exception class/source location, without exception messages or private payloads. |

## Meaning of green

The indicator says **Matches last confirmed server data**. Confirmation is volatile
and revoked on known edits, disconnects, backgrounding, partial refreshes, errors,
and snapshot application. A write acknowledgment alone cannot restore it. Storage
failure cannot mark a snapshot confirmed. Cooking partial updates cannot confirm
the full cooking replica.

No asynchronous client can guarantee instantaneous equality with a server that
may change after its last response. Another device can commit before its broadcast
reaches this device. The guarantee is equality to the latest successfully persisted
canonical confirmation, with no known unconfirmed work; it is not a claim that the
server cannot change. Public recipe cache, unsaved drafts and operational state
are not a full database replica. Authentication is still enforced by the server.

## Verification

- `flutter analyze --no-pub`: no issues.
- `CTR_BACKEND_SOURCE=/home/debian/projects/coffey-table-recipes-vps-audit flutter test --no-pub`: **651 passed**; actual PHP/Dart integration included.
- Backend checks passed: 7 data WebSocket, 10 account WebSocket, 25 meal-plan,
  21 authentication tests; data contracts, restaurant and recipe receipt checks;
  shopping WebSocket checks (optional Home Assistant integration not configured).
- Added fault regressions cover malformed messages, server exceptions, request
  timeout, snapshot/disk failure, lost acknowledgments, token changes, concurrent
  cache writes, stale reads, public-link rendering and conflict preservation.
- Real PHP/Dart contract test uses a disposable database and production transport
  code, including an injected server exception. No production household writes.
- Before deployment, unchanged released Dart source failed a live anonymous
  `/recipes/9` read with “Data synchronization disconnected.” The exact same test
  passed after deployment. This verifies response consumption, not just URL routing.
- Deployed backend source matches all 60 PHP runtime source files checked.
  Health, public recipe and both association endpoints return HTTP 200.
  Container running, no OOM/restarts; CPU policy unchanged. Deployment preserves
  existing private configuration and persistent state and performs no migration.

These checks cover data synchronization paths and representative injected failures;
they cannot prove the absence of every undiscovered defect. A physical iPad
multi-device acceptance check remains necessary for the next installed build.

# Shopping synchronization migration

Task branch `migration/shopping-websocket`, based on `cac5c66` from `origin/main`.
The backend uses its existing `migration/vps-backend` branch; the HA repository
uses its own `migration/shopping-websocket`. All three await user approval before
merging. Source changes do not authorize app builds, installation or cutover.

Shopping transport defaults to `wss://ctr.coffeybean.com/shopping`, overridable
with `SHOPPING_SOCKET_URL` for an isolated test environment. Other operations keep
the existing inMotion API. Firebase credentials are sent in the first encrypted
WebSocket message, never in a URL. The socket becomes ready only after server
authentication and durable installation of its household snapshot.

LocalData remains the shopping source for reads, edits and the durable outbox.
WebSocket pushes merge with pending local edits and persist before repainting.
Stable change IDs/timestamps and explicit acknowledgements survive lost responses
and restarts. A newer push cannot be rolled back by a delayed acknowledgement.
Department edits persist locally and carry their base configuration so concurrent
configuration changes can reject safely. Legacy household snapshots neither
replace nor remove shopping state, including while a clean list has no pending
edits. A new device must download shopping data once before editing it offline.

Connections send heartbeats, reconnect with bounded backoff, refresh Firebase
tokens, renew before expiry, and reconnect on app resume. The small green
`Icons.cloud_done` icon is immediately left of the account badge only while
shopping is open and its household connection is ready. It has no added label,
tooltip or action and does not claim that the outbox is empty. Mobile OS
suspension can interrupt connections; durable synchronization resumes afterward.

The backend repository documents its normal deployment entry point in
`docs/shopping-websocket-migration.md`. Deployment includes credential preparation,
journal preservation, Caddy/TLS and retirement of the old shopping HTTP routes.
This app branch already uses the VPS; there is no separate cutover switch.

Verified on 2026-10-28 using the shared development container and Flutter 3.47.8:

- `flutter test --no-pub`: all 528 tests passed in the single full-suite run.
- After the final per-transport upload-readiness adjustment,
  `flutter test --no-pub test/shopping_push_test.dart test/shopping_socket_test.dart test/local_data_test.dart test/snapshot_database_test.dart test/account_timer_menu_test.dart`:
  all 61 tests passed. This includes the new regression proving shopping uploads
  proceed when the recipe HTTP transport is offline. The full suite was not
  repeated for this bounded follow-up.
- `flutter analyze --no-pub`: no issues in the final source.
- Changed Dart files formatted; `git diff --check` passed.

No app packages were built. The prepared VPS endpoint subsequently passed a live
authenticated public WSS read and open-connection credential revocation check.
Real-user Firebase sign-in and physical-device checks were not performed.

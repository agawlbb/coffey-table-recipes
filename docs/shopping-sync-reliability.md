# Shopping synchronization prevention

This change prevents new lost moves/deletions and silent, indefinitely pending uploads. It does not rearrange the household's corrected shopping items, replay historical conflicts, reset device storage, or modify memberships.

## Device guarantees

- Local-first shopping waits for the durable LocalData write before showing a deletion as complete. A device-storage failure retains the visible item and reports the actual storage error.
- LocalData is the single shopping source in local-first mode; the older secondary ShoppingListCache is neither read nor overwritten there. Legacy non-local-first callers retain their existing cache behavior.
- Each new shopping write persists its original base items, stable `client_change_id`, and original `edited_at_ms` before upload. Retries/restarts reuse that identity and time. A server response must acknowledge the same change ID before the outbox is cleared.
- An interrupted send with a shopping change ID is safely replayable after restart. Lost acknowledgement or local failure recording acknowledgement retains the operation for retry, rather than permanently marking an ordinary shopping retry as an unknown creation.
- Incoming household snapshots overlay only pending shopping changes onto fresh server items. Unrelated additions/edits remain visible, while pending deletions do not resurrect. Same-revision content changes also repaint the shopping screen.
- The shared LocalSyncStatus is now mounted in the account screen. Unconfirmed writes remain visible; overdue status includes the latest error and HTTP status. Pending edits remain durable. A fresh valid account response re-enables token-blocked uploads, without bypassing server authorization.

## Compatible server protocol

`POST /households/{id}/shopping-list` retains the legacy revision/items contract and additionally accepts `base_items`, `client_change_id` and `edited_at_ms`. New writes merge only the fields/order changed between the base and desired items; they do not replace unrelated server edits. The response contains the current canonical list plus `acknowledged_change_id`.

The existing household row lock commits items, per-field edit clocks, deletion tombstones and receipt hashes together inside the existing JSON envelope. Receipt replay returns the current canonical list without another mutation; changing a payload under an existing ID is rejected. Older offline edits cannot supersede newer user edits or resurrect newer deletions. Equal edit times use the stable change ID as a deterministic tie-break. Internal synchronization metadata is not exposed by read/snapshot endpoints. There is no schema migration.

Old clients remain revision-guarded. A stale legacy retry is acknowledged only when its entire desired list already exactly matches the authoritative list (including order, notes and departments). A differing stale request still fails safely instead of overwriting the current household list.

The backend emits `X-CTR-Time-Ms`, exposed for browser clients. RecipeApi samples that trusted response time; LocalData preserves its server-time offset and original edit timestamp. Receipt time/retry time never makes an older action newer. Edits more than five minutes ahead of server time are rejected with a clock/retry error. Calibration carries network-delay uncertainty, and before a device has a time sample its wall clock is the fallback; exact physical ordering of nearly simultaneous edits or independently offline, incorrectly clocked devices cannot be proven. The stable tie-break makes convergence deterministic. Metadata/receipts are retained to preserve replay and deletion safety.

## Verification and rollout

Focused coverage includes a single user losing the server's delete response, device restart, stable retry identity/time, missing acknowledgement, durable UI deletion, storage failure, stale secondary cache, snapshot overlay, authentication recovery, and older-edit suppression. Server fixtures also cover legacy retries, idempotence, independent field merging and unchanged authorization/department behavior.

Verified on 2026-10-24 with the isolated Flutter 3.47.8 / Dart 3.13.7 SDK: all 518 app tests passed in the single full-suite run; focused persistence/shopping/transport checks passed during iteration; final affected-file analysis is clean. PHP fixtures `shopping_lists.php`, `household_snapshot.php`, `shopping_sync_requests.php`, and `home_assistant_connections.php` passed using ephemeral SQLite data. No app packages were built for this source change.

Deploy the backward-compatible backend before distributing new clients. No live shopping data is edited as part of deployment. Native/web app builds require explicit build/release authorization separately from this source change. Physical Android reproduction of the original incident and its original HTTP response remain unverified; the one-minute notification alone does not identify the original transport/server failure.

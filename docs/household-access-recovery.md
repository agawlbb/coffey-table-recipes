# False household-access removal

The local repository previously treated any HTTP 403 as revocation of the entire household. An action-level denial (`child_mode`, `permission_denied`, or `ai_images_disabled`), or an unstructured proxy response, could therefore remove downloaded records and archive pending edits even though household membership remained valid. An expired token also erased local data. Administrator status did not prevent this client-side classification error.

Local invalidation now follows authoritative API error codes: `household_not_found` removes that household's access; `account_disabled` and `account_deleted` remove account access; `recipe_not_found` invalidates the requested recipe resource. Other failed requests still fail, and rejected writes remain pending for review, but do not revoke unrelated local access. Server authentication, membership, child-mode, and role checks are unchanged. A valid `/me` response that omits a household still revokes it; malformed membership responses cannot be mistaken for an empty membership list.

A successful membership refresh clears legacy household blocks and discards their stale snapshot version so the next download cannot return an unchanged receipt for records the old client deleted. Existing archived drafts remain preserved for review rather than being automatically replayed. Confirmed revocation also removes snapshot metadata, and late responses cannot restore revoked data or spread another household's denial.

## Validation status

Added regression coverage to `test/local_data_test.dart` for action-level denials, token failures, preserved local edits, malformed account responses, actual account/membership revocation, legacy-block recovery, and cross-household response races. Existing snapshot and child-mode callers are the focused companion scope.

Source and diff review only on 2026-10-24: Dart formatting, analysis, and runtime tests were not run. The repository requires Flutter >=3.47.8 and Dart >=3.13.7; the shared installed SDK is below those minima and under the security coordinator's hold. Do not bypass that hold with `--no-pub` or an SDK override. Once permitted patched tooling is supplied, format/analyze the changed Dart files and run `flutter test --no-pub test/local_data_test.dart test/snapshot_database_test.dart test/child_mode_test.dart`.

No household memberships or roles were changed. No app build, installation, backend deployment, or shared SDK modification is part of this change.

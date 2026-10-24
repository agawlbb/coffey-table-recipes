# False household-access removal

The local repository previously treated any HTTP 403 as revocation of the entire household. An action-level denial (`child_mode`, `permission_denied`, or `ai_images_disabled`), or an unstructured proxy response, could therefore remove downloaded records and archive pending edits even though household membership remained valid. An expired token also erased local data. Administrator status did not prevent this client-side classification error.

Local invalidation now follows authoritative API error codes: `household_not_found` removes that household's access; `account_disabled` and `account_deleted` remove account access; `recipe_not_found` invalidates the requested recipe resource. Other failed requests still fail, and rejected writes remain pending for review, but do not revoke unrelated local access. Server authentication, membership, child-mode, and role checks are unchanged. A valid `/me` response that omits a household still revokes it; malformed membership responses cannot be mistaken for an empty membership list.

A successful membership refresh clears legacy household blocks and discards their stale snapshot version so the next download cannot return an unchanged receipt for records the old client deleted. Existing archived drafts remain preserved for review rather than being automatically replayed. Confirmed revocation also removes snapshot metadata, and late responses cannot restore revoked data or spread another household's denial.

## Validation status

Added regression coverage to `test/local_data_test.dart` for action-level denials, token failures, preserved local edits, malformed account responses, actual account/membership revocation, legacy-block recovery, and cross-household response races. Existing snapshot and child-mode callers are the focused companion scope.

Source and diff review only on 2026-10-24: Dart formatting, analysis, and runtime tests were not run. The repository requires Flutter >=3.47.8 and Dart >=3.13.7; the shared installed SDK is below those minima and under the security coordinator's hold. Do not bypass that hold with `--no-pub` or an SDK override. Once permitted patched tooling is supplied, format/analyze the changed Dart files and run `flutter test --no-pub test/local_data_test.dart test/snapshot_database_test.dart test/child_mode_test.dart`.

No household memberships or roles were changed. No app build, installation, backend deployment, or shared SDK modification is part of this change.
## Authorized repair release validation — 2026-10-24

Joe subsequently authorized the SDK update and repair release on all platforms. CTR owner granted exclusive source/build/signing access and confirmed the FanControl signing handback. Installed official Flutter 3.47.8 at exact tag revision `737ba8f885dc774b53b442759999a312c9461e4e` in ignored `build/tools/flutter-3.47.8`; runtime reports Dart 3.13.7. The shared SDK and global PATH remain unchanged. Enabled Git long-path handling only in this new SDK copy to complete the official checkout. No alternate project checkout or SDK-floor bypass was used.

Formatted `lib/src/local_data.dart` and `test/local_data_test.dart`; affected-file analysis passed. One focused invocation of local_data_test.dart, snapshot_database_test.dart and child_mode_test.dart passed all 62 tests. Full-project analysis and the complete release suite passed all 509 tests using this patched SDK. No behavioral source correction was needed. Release workflows are pinned to 3.47.8. Existing Firebase versions/configuration remain unchanged under the owner's wait decision.

These are source/regression checks, not proof of the reported physical iPhone cause or recovery. Production memberships, roles, local device data and pending edits were not reset. Archived drafts remain preserved for review. Platform delivery and installed-app validation are recorded under 2.1.2 in docs/releases.md.

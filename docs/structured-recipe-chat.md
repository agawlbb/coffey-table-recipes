# Structured working recipe chat

Task `feature/structured-recipe-chat` starts from fetched app main
`9c840e26b3b61bbdcb7f0938986e6bcb3d006f6c`, preserving the earlier review/save
feature through `155faa4652d8ce12c6c8893cf8dc78aa381194dd`. The VPS companion
branch starts from main `b8c0b24f9c04981f1604f52ddc13244b9a3007e2` and preserves
deployed chat/SQL context through `98a82fa60f1838e282e3eaca058bf6c5dd15b076`.
No main merge is authorized.

AI now returns concise prose and validated changes to one server-held structured
working recipe. It no longer repeats complete recipe drafts on every turn. The
server supplies only the current recipe, a bounded recent conversation and scoped
preferences; undo uses server snapshots. The full local human transcript remains
available. Review validates and opens editor data locally with no new AI call.
The existing prepare request remains to check live access and original revision;
there is still a network round trip, not another AI generation.

The app requires the structured working_recipe response and shows a brief
Opening recipe for review indicator. When local validation needs essential
information, it returns to Chat and shows only the missing fields. Review/save
destination, retry identity and editor Save remain as previously implemented.
New variations omit automatic original-photo copying to avoid delaying review;
edits retain their photos. Existing editor photo controls remain available.

The VPS keeps private per-operation token/call/timing metrics and a CLI report.
A real synthetic three-turn session used 508/178/51 output tokens for creation,
a targeted edit, and exact server undo. Review used zero AI calls/tokens and
about 6 ms server processing; real network/device latency is additional. No
historical full-session token baseline exists, so there is no claimed percentage
saving. Older text-only sessions may need one conversion before subsequent
reviews become local; original caches are retained.

2026-11-01 validation: 39 focused Flutter tests passed via
`flutter test --no-pub test/recipe_chat_test.dart test/recipe_import_methods_test.dart test/recipe_variation_test.dart`.
Changed Dart files were formatted; focused analysis found no issues. Backend
working document, patch atomicity, quantities/actions, undo, schema/identity
protection, history/preference bounds, legacy recovery and actual token accounting
have focused PHP and real-socket coverage. Live provider testing used only a
synthetic recipe and no production recipe/context. No app build, release, web
deployment or main integration is part of this feature implementation.


VPS structured-chat source `5342aa0` was deployed and verified healthy on
2026-11-01. Its source/private-configuration hashes, CPU policy, public health
and invalid-token authentication checks passed. An existing authorized recipe
normalized successfully in a read-only deployed runtime check without AI/data
writes. The current test client can use the faster backend flow. No new app
package was built; these app source changes remain on the task branch. Both
main heads are unchanged and all earlier task branches remain intact.


## Authorized Android test build 50

The user requested another Android test APK once implementation was complete.
Reserve base build 49 so the existing test workflow's +1 produces build 50,
newer than delivered test build 49. The existing version label remains
`2.5.0-account-test`. Existing 39 focused checks/analysis cover this source; only
the build reservation and documentation change for packaging. No main merge,
release, web or iOS build is requested.


### Verified Android test delivery — 2026-11-01

[Android build job](https://github.com/agawlbb/coffey-table-recipes/actions/runs/41336231037)
passed for immutable app source `3e7c1d99420697fc3c8e64751f8350961e3277f2`.
The workflow verified the existing app identity, version/build, non-debuggable
release mode, original signing certificate, required Android timer JNI classes
and hosted Android app links. Downloaded artifact bytes matched the workflow
SHA-256 and its source/build/certificate report. Existing focused source
validation remains valid; packaging changed only the version reservation.

- Version `2.5.0-account-test`, build **50**.
- Filename: `CoffeyTableRecipes-2.5.0-account-test-build50-3e7c1d9.apk`.
- SHA-256: `807966c8467b3ff127ca18179fc916d65f296aad6bec4423c90aa98c0e5f1194`.
- Signing certificate SHA-256: `f8de933f14b9bb4b3191a94aedc8637972c5ab224565f6abd7808f8038d12097`.
- [Download verified Android test APK](https://drive.google.com/file/d/1YO7LEXn4ATDb7XmMsE43HXE-EVknal9z/view).

The configured recipe app Drive folder was used. Uploaded bytes were downloaded
and their SHA-256 matched. All existing visible Drive file IDs were retained;
no APKs were removed, sharing changed, or release notification sent. No APK
is publicly hosted on the VPS. No main merge, release tag, web/iOS build or
device installation is included. Both feature repositories remain unmerged.


## Remove instructional filler

Removed the chat's workflow-explanation banner and canned opening instructions.
The chat starts empty, with Message AI identifying the input. Working recipe uses
the concise empty state No recipe yet. Successful review does not add a redundant
chat announcement; actual missing-field questions and errors remain visible.
AGENTS.md now explicitly requires intuitive controls and prohibits unsolicited
instructional filler. No backend, app build, release or main merge is included.

Validation for the copy cleanup: `flutter test --no-pub --concurrency=1
test/recipe_chat_test.dart` passed all 30 checks. Changed Dart files were
formatted and focused analysis reported no issues. Existing tests were updated
for the empty initial chat; no cosmetic-only test cases were added.

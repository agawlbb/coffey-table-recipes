# Combined cooking plans

Task branch: `feature/combined-cooking` in the Flutter and VPS repositories.
App base: `d0bc41f`; backend base: `759167f` (fetched canonical main).

The meal planner's Cook together action opens a dish selector, initially selecting
all available recipes on that date. Dinner time starts from Settings → Dinner
time (initially 6 pm). Notes, restaurants and unavailable recipes cannot supply
cooking instructions and are excluded. The planner currently has no separate
portion override: selected dishes retain their recipes' stored quantities/yields.

The existing authenticated AI transport sends selected entry IDs, date, dinner
instant and a session identity to `/households/{id}/cooking-plan`. The backend
resolves recipe contents under the caller's access and uses that user's existing
private cooking context. AI returns relative scheduling offsets for original
steps, allowing passive cooking/resting to overlap other dishes. Instructions,
quantities, component groups, timer ranges and appliance settings stay intact.
Each combined step retains its source recipe and step identities. Duplicate dishes
have distinct session identities. No step-estimate database columns are added.

Generated plans are retained separately from live sessions. The cache includes
recipe cooking snapshots, quantities, selected-dish multiplicity, user/household
and personal context. Dish selection order and dinner date/time do not invalidate
an otherwise identical relative plan. Reuse creates fresh progress. A lost-response
retry with the same session identity returns the existing accessible session.

Opening, sharing or chatting does not start cooking. Start cooking or completing
any step starts the session. Before starting, expiry is one hour after scheduled
dinner; afterward existing foreground/inactivity and running-timer rules apply.
Changing dinner time shifts suggested times directly without AI and preserves
completed work and timer deadlines. Steps on another day include that date.
Saved sessions remain readable offline; starts, completion and dinner shifts use
the existing local-first operation transport.

Provide feedback opens a private, per-author chat. Opening reloads saved history
without calling the model. Each submitted message first synchronizes pending
progress; the server supplies fresh completion, timers, viewed-step data, dinner
and current time, timeline, conversation and the author's private context. AI may
return revised remaining offsets and supported personal-context updates. Shared
participants receive timeline changes, while conversations and saved personal
facts belong to their author. Completed step schedules and running timers survive
updates. If progress changes while AI is thinking, its stale timeline is not
applied; the chat reports that another message can adjust the latest plan.

## Device alarms

After generation/reuse, Android/iOS offer an optional start alarm. Long-pressing
a combined session in the navigation drawer offers Set/Remove start alarm and
Share. A small alarm icon indicates a future alarm on this device. Setting an
alarm joins the device to the session for existing synchronization, but does not
start cooking. Ordinary recipe sessions retain their existing long-press sharing.

Start alarms use a distinct account/session key and existing native permissions,
sounds and notification preferences. Dinner/AI shifts update accepted alarms;
starting, ending, expiry or a newly past start cancels them. Silent shared-session
updates modify only devices with an existing opted-in alarm. They never opt other
devices in. Native background delivery is best effort; reconnect reconciles state.
Alarm delivery/dismissal does not start cooking.

## Validation and delivery

Focused checks and delivery verification are recorded below when complete.
No full app test suite, app build, release or main integration is authorized by
this task. Widget/channel fixtures do not prove physical-device alarm delivery or
real-model scheduling quality; those remain acceptance checks for an explicitly
requested native build and a real cooking trial.

2026-11-07 source verification:

- Changed Dart files formatted; scoped analysis of the eight affected library
  files and three affected test files passed with no issues.
- `flutter test --no-pub --concurrency=1 --reporter expanded test/combined_cooking_test.dart test/cooking_sessions_test.dart test/cooking_mode_test.dart test/account_timer_menu_test.dart test/client_log_test.dart`: all 44 passed.
- The earlier focused run also passed every case in `test/timer_sync_test.dart`,
  `test/meal_planner_test.dart`, `test/backend_socket_test.dart` and
  `test/local_data_test.dart`. Its four failures in other files were corrected:
  alarm-state completion, new preferences setup, and cooking UI diagnostic-timer
  isolation. Two intermediate attempts at asynchronous diagnostic cleanup were
  stopped after stalling; neither is counted as passing. Logger behavior itself
  remains covered by the seven passing dedicated logging tests.
- Backend: 27 new plan checks, existing cooking-session checks, AI configuration
  and timer-push checks passed. A real local WebSocket test with disposable SQL
  and a fake provider passed generation, cooking broadcasts, dinner shifts and
  feedback/context persistence. Changed PHP syntax and Git whitespace checks passed.

No live AI-provider evaluation, physical-device alarm test or app build was run.
Main integration remains pending explicit acceptance.

The backend implementation `38db9ec` is deployed. Its 66 checked installed source
files match the task branch; HTTPS health returned 200/ok and required CPU settings
were verified. Deployment ownership/read-permission failures were corrected before
verification; details are in the backend's COOKING-PLANS.md. No app package was built.

## Signed Android test APK — 2026-11-07

At the user's explicit request, [Android build 42397924161](https://github.com/agawlbb/coffey-table-recipes/actions/runs/42397924161)
successfully built immutable source `207314b8f9b795f246290dba1d3d0605925f603e`
in the existing test-build mode. Package `com.coffeytable.coffey_table_recipes`,
version `2.8.1-account-test`, build **65**. The source version was not changed.

Delivered [CoffeyTableRecipes-2.8.1-combined-cooking-test-build65.apk](https://drive.google.com/file/d/1zB2yKqo6R3BhDCjZuSarKhnn7gzFF7RS/view)
to the existing recipe-app Drive folder (71,775,897 bytes).

- APK SHA-256: `3c347b152ec29a841e4868964a6479bbcc3590c1373904a36a44b42d84c26143`.
- Original certificate SHA-256: `f8de933f14b9bb4b3191a94aedc8637972c5ab224565f6abd7808f8038d12097`.
- Workflow verification passed exact source/version/package identity, signature,
  non-debuggable status, required timer-preferences JNI classes and hosted app links.
- Independent local checks passed APK checksum, apksigner certificate/signature,
  aapt package/version/non-debuggable metadata, 16 KiB alignment and
  `python3 tool/verify-app-links.py --fingerprint ACTUAL_CERTIFICATE_SHA256`.
- The uploaded Drive APK was downloaded and its SHA-256 matched. All existing
  files and sharing settings were retained. No release notification was sent.

This supersedes the earlier no-build status for Android only. No full test suite,
iOS/web build, release tag, main integration, device installation or live AI call
was performed. Actual alarm delivery and cooking quality still need user/device
acceptance. Generated packages and private credentials remain outside Git.

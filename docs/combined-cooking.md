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

## Follow-up: reasoning and Android layout — 2026-11-07

The reported saved response really compressed a 12–15 minute simmer to eight
minutes and an 8–10 minute bake to one minute; this was AI output, not clock
conversion. Initial diagnostic calls used the globally pinned Mini model with its
default no-reasoning setting. Prompt wording alone did not repair the fixture;
reasoning attempts could exhaust the previous 10,000 output-token allowance.

Cooking generation and feedback now use `gpt-6-luna`, explicit high reasoning and
a 25,000 output-token allowance. Other recipe AI operations retain their existing
settings. The prompt explicitly works backwards from all dishes ready to serve,
uses upper timer ranges, reserves handling/heat-up time and coordinates one cook.
AI still chooses the schedule; no server scheduling engine or recipe-step estimate
columns were added. Cache identity includes the actual planner settings and prompt,
so previous results do not satisfy the corrected request. Incomplete responses
preserve the current plan and report an actionable error; only failure metadata is
logged. Successful usage metadata is retained with the private saved result.

The planner now has a Cook together text action. The cooking header puts editable
time and Keep awake on one row, using flexible text on narrow phones. The selector,
long-press alarm/share sheet and member selector protect their bottom controls
with explicit safe areas. Existing controls and start rules retain their behavior.

Validation: scoped analysis passed; all five combined-cooking tests passed with
navigation insets, button/member tap flows and a 320-pixel header. The other 40
cooking-session/planner cases passed during the focused runs; initial genuine
narrow-layout failures were fixed and the affected files rerun. Backend: 30 plan
checks and the real local cooking-plan WebSocket scenario passed. Live isolated
fixtures passed soup/bread (6,222 total tokens), four dishes (11,702 tokens), and
progress-aware feedback (5,904 tokens), including full explicit duration ranges
and no broiler/soup-finishing conflict. These are bounded evaluations, not proof
of all cooking estimates. No production recipes were used as test fixtures.

The source build counter advances to 65 so the existing test workflow produces
Android build 66, distinct from the previous test APK; version remains 2.8.1.
Main integration and physical-device acceptance remain pending.

The follow-up backend `bf0cf2c` is deployed with 66 matching installed source
files, HTTPS health 200/ok and required CPU policy verified. At the user's request,
the reported old soup/bread session was removed from active plans and its single
matching cached AI response deleted; recipes and personal context were preserved.
The standard cancellation tombstone remains for device reconciliation. Android
test build 66 is dispatched from immutable source `591bc307bebe7b70019e81239b76d443f748c90c`.

## Verified follow-up Android test APK — 2026-11-07

[Android run 42402856114](https://github.com/agawlbb/coffey-table-recipes/actions/runs/42402856114)
successfully compiled source `591bc307bebe7b70019e81239b76d443f748c90c` in test
mode. Package `com.coffeytable.coffey_table_recipes`, version
`2.8.1-account-test`, build **66**. The verified file is
[CoffeyTableRecipes-2.8.1-combined-cooking-test-build66.apk](https://drive.google.com/file/d/1qDLuueVdBrYSYqvp3hNt_zHKvT1NeGDq/view),
71,775,897 bytes, SHA-256
`e5c0b21e8ba516eec87baf35a16d35d0574f33454e9b7500363b0c60a37fdb5e`.

Workflow and independent local verification passed original signing identity
`f8de933f14b9bb4b3191a94aedc8637972c5ab224565f6abd7808f8038d12097`,
package/version/build, non-debuggable status, exact source/checksum, 16 KiB
alignment and hosted Android app links. The workflow also verified timer JNI
classes. The Drive APK was downloaded and its SHA-256 matched. Existing files
and sharing settings were retained; no release announcement was sent.

No full test suite, iOS/web build, release tag, main integration or device
installation was performed. Actual Android navigation and alarm behavior remain
for device acceptance with this APK. AI evaluations remain bounded to the three
recorded fixtures; user feedback can refine future estimates.

## Full preparation, start-alarm times and clearing — 2026-11-07

AI can now add session-only `prep:` entries alongside every original recipe step.
Each added entry has instructions, selected-dish references and an AI-chosen time;
its stable identity survives session snapshots, feedback, sharing and offline
reopening. Original recipe instructions, quantities and timer actions stay intact.
The prompt requires every task in the checklist rather than preparation before
its first action hidden in notes. There is no server scheduling engine or recipe
schema change. Completing preparation starts cooking under the existing rules.
The earliest checklist entry drives the suggested start and device start alarm,
including the reported 58-minute preparation example.

Start alarms now show scheduled local time in the app-wide bar and alarm list;
other cooking timers retain countdowns. Non-today alarms include a date. Both
setting entry points show the intended time before the user accepts; existing
menu alarms also show their scheduled time. Clearing from the hamburger menu
always confirms, including unstarted or completed sessions. Cancel preserves the
plan and alarms.

Cooking AI now uses Luna with explicit **medium** reasoning and the existing
25,000-token cap. A paired three-meal fixture comparison measured medium median
36.02 seconds and high median 173.91 seconds. Manual review found a crowded
hands-on interval in one medium four-dish result, so the prompt was tightened.
A further three-meal medium check, including explicit active-work overlap checks,
passed at 30.63, 62.03 and 81.93 seconds (median 62.03). This supports medium for
this revision but does not guarantee sub-minute latency or correctness for all
meals. The high baseline was not rerun after that final prompt clarification.
All comparisons used disposable raw-ingredient fixtures, not hosted recipes.
Model/effort/prompt/response-format participate in saved-plan matching; old results
cannot satisfy the new request. Private usage metadata now includes request time.

Validation: the focused three-file Flutter command passed 27 tests covering
combined cooking, session confirmation and timer visibility. The five combined
cooking tests were rerun after adding checks for both alarm-setting entry points
and passed. Scoped analysis of the four affected libraries and three affected
test files passed. Backend passed 37 plan checks plus the targeted real local
cooking-plan WebSocket test, now including a generated preparation entry. The
WebSocket fixture checks prep storage and broadcast; the live model comparison
checks culinary planning and does not prove device behavior.

No app build or main integration is included in this revision. The backend's
complete checklist can be viewed by the existing test app, but the new confirmation
and alarm-display UI needs a future explicitly requested APK build.

Backend `83f4614` is deployed: 66 checked installed files match, public HTTPS
health is 200/ok and the required CPU policy is verified. The user-reported current
soup/bread plan is cleared from active sessions and its one matching saved AI
result deleted. Normal cancellation covers all joined devices; recipes, personal
context and unrelated plans remain intact. No new app build was requested or made.


## Shared connection and day-header follow-up — 2026-11-07

Continued the existing task from app `1166583` and backend `c4bf94b`, without
main integration. Token renewal no longer waits for outstanding requests or
replaces the established connection-ready signal. Same-account renewal runs on
the existing socket while ordinary requests continue. Native cooking/alarm
updates run independently after accepting pushed cooking data; device failures
are reported without failing the incoming socket frame.

Cooking-plan responses no longer write session state back into the cache.
Pushed server state owns it, including changes received while AI or chat history
is loading. Feedback no longer awaits the shared repository's pending saves;
it includes the device's displayed completion, timers, start and dinner state
alongside the server's current progress. Existing stale AI-result handling and
private author context are retained. No new queue, connection, comparison gate,
model setting, database timing field or background polling was introduced.

The Today marker sits above its day card. Date text and both actions share one
row, with flexible text space rather than overflowing or moving the action group
below the date. Current-day styling and toolbar Today navigation remain.

Focused validation passed across `app_connection_test.dart` (3),
`shopping_socket_test.dart` (3), `combined_cooking_test.dart` (8),
`meal_planner_test.dart` (23), and `cooking_sessions_test.dart` (17).
This includes a real Dart/PHP shared connection, pending/timed-out AI traffic
through token renewal, delayed native alarm handling, stale replies, feedback
with an unanswered save, and 320/390px action alignment. Scoped Dart analysis is
clean; changed Dart files are formatted and diffs checked. An existing test was
adapted to find the day card below the new label; alarm tests now allow native
updates to finish independently of accepting server data. No full suite, app
build, live AI call, plan deletion or physical-device check was performed.

The backend retains its existing request-rate and AI capacity protection.
Rate errors identify only the rejected request; heartbeats and authentication
continue on the open connection. Same-account authentication renewal preserves
running workers; changing identity/scope still isolates their work.


## Android test build 67 — 2026-11-07

Requested test APK built from `78a77ffc5b11660a79c96d0f0259037cea962395` using Actions run
[42411830740](https://github.com/agawlbb/coffey-table-recipes/actions/runs/42411830740).
Version `2.8.1-account-test`, build 67, package
`com.coffeytable.coffey_table_recipes`. This includes the complete preparation,
absolute start-alarm times, clearing confirmation, shared-connection fixes and
Today label adjustment. The source build counter advances to 66; the existing
test workflow adds one. Main remains unchanged.

Signed, nondebuggable APK verification passed for the original certificate
`f8de933f14b9bb4b3191a94aedc8637972c5ab224565f6abd7808f8038d12097`. Package/version, 16KiB alignment, native preferences
JNI and hosted Android app links were verified. Uploaded
[CoffeyTableRecipes-2.8.1-combined-cooking-test-build67.apk](https://drive.google.com/file/d/1I8arQ3qscol0hvh5FzmzJCsTodeHiSlS/view)
to the existing recipe app Drive folder and downloaded it for matching SHA-256:
`b23076d56f35070a7bc07d7fbbc3cf90017fe845b31b9b5156ccfedbf449229f` (71775897 bytes).
No older files were removed, release notification sent, live AI evaluation run,
or app/full test suite repeated. Physical-device installation is unverified.


## Notes, Today label, low reasoning evaluation — 2026-11-07

Continued app task from `ffbc903`, backend `6369764`. The cooking screen no
longer renders plan_message above the first step, for existing or new sessions.
Feedback explanations remain in chat; no usefulness classifier, extra provider
request, schema change or connection behavior was added. Today is centered above
its day card, 16 logical pixels and bold. Existing action-row layout remains.

31 focused Flutter checks passed in combined_cooking_test.dart (8) and
meal_planner_test.dart (23), including absence of saved notes, feedback behavior,
Today centering and 320/390px layout. Scoped analysis is clean, changed Dart files
are formatted and diff checks passed. No full suite or new APK was requested/run.

Six live calls compared Luna low and medium with the same current generation
prompt, synthetic raw-ingredient meals, 25,000-token cap and evaluation output
schema. They did not use production recipe or personal-context fixtures.

| Sample meal | Low seconds | Medium seconds | Low result |
| --- | ---: | ---: | --- |
| Soup and garlic bread | 11.10 | 49.90 | Bread finished about 29 minutes early; explanation contradicted its ordering. |
| Soup, bread, vegetables and rice | 11.06 | 94.80 | Butter melting and rice rinsing omitted. |
| Chicken and garlic bread | 9.14 | 28.46 | Slicing chicken overlapped watching the broiler. |

Median elapsed time: low 11.06 seconds, medium 49.90. Median output tokens:
low 1,042, medium 5,346. Medium passed the narrow ingredient-preparation,
explicit-duration and selected hands-on overlap checks in all three samples.
These checks do not establish every implicit heating interval or serving-quality
assumption; manual review still found imprecise heating language in the complex
medium result. Low was faster but inadequate on these samples, so production
remains medium. No automatic fallback or model/settings change was introduced.
The diagnostic's preparation-first assertion was disregarded: preheating before
ingredient preparation is valid. Results remain in ignored build/low-medium-evaluation.

The latest reported soup/bread session had already ended. Its unique matching
reusable cache entry was removed, ensuring the next generation calls AI again.
The normal ended-session tombstone remains for device cleanup. Recipes, personal
context and other plans were untouched. No backend source deployment was needed.

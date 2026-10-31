# AI on the VPS

Working branch `feature/vps-ai-websocket`, based on fetched app main `2920c38`.
Companion branches use InMotion `c5503a3` and VPS `b977c8f`. Keep all three
unmerged until the user approves integration. No app build or release is requested.

Recipe imports, clarification answers, variations, recipe images, category
artwork and parent-category administration use the existing encrypted VPS
WebSocket endpoint with an authenticated `ai` scope. Signup and other account
administration remain on InMotion. Blank saves still use the normal durable
outbox; automatic category selection runs locally on the VPS.

The connection stays open between requests and while users answer existing
clarification questions. The existing forms and review/save behavior stay the
same. During an AI run, those screens (and automatic category artwork in the
browser) display the current stage and elapsed seconds. There are no invented
percentages, new controls, chat screens or new dialogs.

Provider work runs in a small isolated PHP child so shopping, timers and socket
heartbeats stay responsive. Runs are bounded to ten minutes, with progress
updates at least every ten seconds while a stage is running. A lost connection
ends that worker; existing retry/input preservation remains. This does not promise
that a mobile OS will keep an app connected while suspended.

The VPS uses its private `recipe-ai.local.json`, approved for reuse by the user.
The runtime image needs DOM, Poppler and Tesseract from the updated Dockerfile;
routine deployment still copies source and restarts the existing service. No
schema change, new infrastructure or compatibility transport is added. New
category artwork lives on VPS storage; existing InMotion media URLs remain valid.

Production is unchanged
until the matching branches are integrated and published; app builds require
an explicit build or release request.

## Validation — 2026-10-30

- `flutter test --no-pub --concurrency=1`: all 544 tests passed.
- After placing progress beside the existing import/photo actions and adding
  the deterministic 160-second connection regression,
  `flutter test --no-pub --concurrency=1 test/shopping_reconnect_test.dart test/recipe_import_test.dart test/recipe_editor_test.dart test/ai_progress_test.dart`:
  all 40 tests passed. The full suite was not repeated for this bounded follow-up.
- All changed Dart files were formatted. Affected-file Flutter analysis passed,
  followed by analysis of the final three-file follow-up; `git diff --check` passed.
- Companion VPS checks cover real socket progress/heartbeats, clarification on
  the same connection, account/household authorization and mid-run revocation,
  image generation/media, blank-save categorization, child crashes/cancellation,
  private configuration and preservation during deployment. Tests use fake AI
  responses and disposable SQLite; no production records or paid AI calls.
- No app package or backend runtime image was built, no service was restarted,
  and no production deployment or merge into main was performed. Physical-device
  background/suspension behavior and live provider execution remain unverified.

# Add recipe

The left navigation menu's Add recipe opens text/description, website, upload,
and camera options for the selected household. An online connection is required.
Available website recipe pictures are included in the review draft as the cover
with website credit. They can be cropped, rotated, replaced or removed before
Save. Pictures remain in memory across clarification questions and their bytes
are not resubmitted to AI. Blocked website images show an import warning while
the recipe itself remains importable. Import/source-picture tests and analysis
pass, including cover/credit preservation through questions and Save.
PDF, JPEG, PNG, WebP and UTF-8 text files up to 5 MB are accepted. Camera images
are resized to 2400 pixels and JPEG quality 85 before upload. Existing iOS camera
permission descriptions apply; browser camera access depends on the browser/device.

The importer accepts HTTP and HTTPS links; the backend upgrades HTTP to HTTPS.
The authenticated backend extracts Recipe JSON-LD first, otherwise removes page
noise. It follows a bounded set of redirects after checking every destination.
If direct extraction fails, the same AI request can use cached public web search
on the original website, retaining a verified canonical recipe source. A missing
or mismatched source returns an actionable paste-text error rather than an
invented recipe. HTTP/HTTPS frontend tests and shared-import regressions pass.
The backend retains its website security checks:

October 12, 2026 verification: 18 import/share tests and Flutter analysis pass.
Backend deployment 6711c43 completed successfully. In the built-in browser,
the exact original HTTP Food Network recipe3.html link reached Review recipe
through the hosted API with eight ingredients and seven steps. Cancel returned
to Recipes; no recipe was saved. The local web app was rebuilt. No frontend push,
release, or macOS runner build was triggered.
use the final URL or paste the recipe. DNS is checked and pinned to a public IP.
Optional Poppler `pdftotext` and Tesseract OCR run locally on the server with a
15 second timeout. Useful extracted text goes to AI instead of file/image data;
sparse or unavailable extraction falls back to AI document reading. Plain text
files are decoded on the device. Original uploads are temporary and not retained.

AI returns a database draft and up to eight clarification questions. Answers can
be “unknown”, and users can review with missing details. Review uses the existing
recipe editor; only Save inserts the recipe and its ingredient/step rows. Imports
use the active household and account, never hardcoded IDs. Save is transactional,
and a stable import key prevents a repeated save from creating a duplicate.

Server setup, endpoint contract, limits and validation are documented in the PHP
repository's `docs/recipe-ai-import.md`. No database migration is required.

Validation: widget tests exercise description/questions/review/save, retained
input after an AI error, and local text upload preprocessing. Existing editor
tests cover field validation. Live AI, device camera and authenticated hosted
saving require server configuration and an authorized deployment/release.

On October 11, 2026, Flutter analysis passed and all 84 Flutter tests passed.
Backend validation passed 21 offline AI preprocessing checks, 35 disposable
recipe edit/create checks (explicitly authorized by the user), and PHP syntax
checks. No live AI API calls, hosted database changes, or deployment were made.

2026-10-16: Existing category IDs take precedence over AI proposal text in review. Matching known labels resolve to existing choices. Choosing a different parent selects that root and discards the rejected proposal; choosing a child saves its ID. Self-named child proposals resolve to the root. Four category-selection regressions include reviewing an imported proposal and capturing the saved parent/child selection payload.


2026-10-16 connection/error handling: import now distinguishes connection failures,
preparation timeouts and incomplete draft responses while retaining the original
input for retry. API decoding preserves HTTP status for non-JSON hosting/proxy
errors, including 401 refresh handling, without exposing HTML or diagnostic
contents. Import logging records failure type and stack location only, never
source text or credentials. The actual informal breakfast-ring AI response was
replayed through the import screen and opened review without saving a recipe.
47 API/import/variation/replay checks passed; Flutter analysis was clean.

Local DNS resolution for coffeybean.com failed during investigation, even after
clearing the transient lookup cache. Public DNS and an HTTPS request using the
public address with normal hostname verification confirmed that the hosted
endpoint accepted both the exact source and a control request (expected 401
without authentication, with localhost CORS headers). No DNS-server, VPN,
certificate, or application endpoint settings were changed.

The conversational backend fix abb83db deployed successfully in Ubuntu Actions
run 38913942056. Local web rebuilt successfully with connection/timeout messages;
published main.dart.js matched the build. No hosted Flutter deployment or iOS
build was triggered.


## Conversational dish creation

**Create a dish with AI** is an Add recipe import method available to every
household; it does not depend on AI image privileges. It opens a messaging-style
chat with labeled You/AI bubbles, a message composer, Send, and an AI thinking
indicator. Users can develop a dish, ask for improvements, compare approaches,
and discuss the effects of substitutions. Questions about hypothetical changes
are discussion, not acceptance of those changes.

AI keeps the currently agreed cooking specification separately from the visible
conversation. Readiness exposes **Review recipe** without ending the chat. Only
that explicit action standardizes the agreed dish through the existing importer;
any remaining importer questions return to the chat. The normal review editor
and **Save** remain the only way to create a recipe. Cancelling review returns to
the conversation; a later message invalidates the previous prepared draft.

All new backend functions are in `agawlbb/coffey-table-recipes-vps`, using
`/households/{household}/recipe-chat` over the existing authenticated VPS AI
WebSocket scope. Shared hosting has no new endpoints or AI functions. Private AI
configuration is reused; no database migration, new credential or infrastructure
is required. Chat requests bypass saved-recipe cache updates. Lost-response
retries recover the same session/turn before a different message can be sent;
definitive provider rejections allow editing the failed message. Conversations
are private temporary working drafts, not a saved chat history or resumable inbox.

Implementation branch: `feature/ai-dish-chat`, app base
`0f5c38bd7dbf13027b750e4f58b59d7bf889c09c`, VPS base
`1257a920f9c09e1c6ca0407ee3dbb0fc315895f9`. This feature remains unmerged until
explicit user approval. Source publication does not deploy or build the app.


### Feature validation — 2026-10-31

- Changed Dart files formatted; affected-file analysis passed. Final chat/test
  follow-up analysis also passed.
- `flutter test --no-pub --concurrency=1 test/recipe_chat_test.dart`: 17 passed,
  including messaging, hypothetical discussion, create/variation/edit save routes,
  lost-response recovery, cancel/late-response handling, failed saves, retained
  variation cover/explanation and enlarged-text/keyboard layout.
- `flutter test --no-pub --concurrency=1 test/recipe_chat_test.dart test/recipe_variation_test.dart test/child_mode_test.dart`:
  33 passed before the final cover/explanation follow-up; the final chat-only run
  above covers that follow-up. Existing family and child-mode regressions remain.
- `flutter test --no-pub --concurrency=1 test/recipe_import_test.dart test/recipe_import_methods_test.dart test/shared_recipe_import_test.dart test/recipe_editor_test.dart test/blank_recipe_detail_layout_test.dart`:
  51 passed.
- API, shopping-socket and offline-cache suites passed in the initial combined
  run. That run exposed initial chat test/layout failures, corrected and verified
  in the focused runs above. The full Flutter suite was not run.
- VPS validation: 81 chat fixture checks, 92 existing variation checks, 294 import
  preprocessing/validation checks, AI worker recovery/cancellation checks, PHP
  syntax checks and 10 AI socket integration tests passed. Providers are mocked;
  wire tests use disposable SQLite, including households without AI image access,
  cross-household denial and preparation without saved-recipe mutations.
- No paid/live-provider request, device run, app build, production-data change,
  deployment, service restart, release or merge was performed. GitHub main moved
  independently during implementation; this feature retains its recorded bases
  and must be integrated/tested against main only when merging is authorized.


### Authorized backend deployment and Android test build — 2026-10-31

The user requested deploying this backend branch and building a test Android APK.
Current accepted main was merged INTO both feature branches to preserve the
completed VPS routing/media cutover and Android preferences startup repair; no
feature was merged into main. The app integration commit is `90917ba`; the VPS
integration/deployed source commit is `8dc297aabcaedf7fa1bd01b7eecc303e50c74774`.

Post-integration validation: affected Dart analysis passed and
`flutter test --no-pub --concurrency=1 test/recipe_chat_test.dart test/recipe_variation_test.dart test/child_mode_test.dart test/api_test.dart test/backend_socket_test.dart test/offline_recipes_test.dart`
passed all 105 tests. Dependencies were resolved from the existing offline cache
because main's accepted Android dependency inputs changed. VPS chat (81 checks),
variation (92), import (294), worker recovery, 10 AI socket tests, 4 deployer tests,
34 HTTP checks and media-preservation fixtures passed. No full-suite rerun.

The existing source-copy deployer replaced only VPS code and restarted the one
backend process. Deployed files were hash-verified against the source commit;
private configuration hashes and the persistent state-directory identity were
unchanged. Docker CPU shares remain 1024 with unlimited cpu.max. The build counter
is advanced to 45 so the existing test workflow produces signed build 46,
`2.4.0-account-test`, without colliding with the previously delivered build 45.
This is a feature test, not a release, and does not authorize iOS/web builds or
merging the feature into main.


### Verified Android test delivery — 2026-10-31

Signed Android **2.4.0-account-test, build 46** was built from immutable app source
`9754546d62ea6d29a8833832f9ba8a571ed3cb30` by
[Actions run 41232863162](https://github.com/agawlbb/coffey-table-recipes/actions/runs/41232863162).
The run completed successfully. The workflow verified the retained Kotlin JNI
classes needed by Android timer preferences before accepting the APK.

- APK: `CoffeyTableRecipes-2.4.0-account-test-build46.apk` (70,014,442 bytes).
- SHA-256: `f1c4dc48edb9422d85bba21587d31075ab392c6ac61dafd67dfe6e06588817f5`.
- Original certificate SHA-256:
  `f8de933f14b9bb4b3191a94aedc8637972c5ab224565f6abd7808f8038d12097`.
- Package `com.coffeytable.coffey_table_recipes`, version/build, non-debuggable
  status, compiled `ctr.coffeybean.com` recipe-link route, checksum and exact source
  were independently verified after downloading the Actions artifact.
- `python3 tool/verify-app-links.py --fingerprint ACTUAL_APK_CERTIFICATE_SHA256`
  passed using that actual certificate.
- [Download the verified test APK](https://drive.google.com/file/d/1Tiix3CWmRw22OBJ5hdEiTJ4pAzxDh9u1/view).
  The existing pinned recipe app Drive folder and restricted OAuth configuration
  were used. Uploaded bytes were downloaded from Drive and SHA-256 matched.
  No existing Drive file was deleted, sharing changed or notification sent.

The VPS feature backend remains running with installed source matching the feature
branch. Both branch working trees are clean and published; neither feature branch
was merged into main. No release tag, web/iOS build or hosted Flutter deployment
was made. Physical-device installation, OS link-resolution and a signed-in live AI
conversation remain unverified; source/widget/wire and deployment checks are
recorded above. Install the signed test APK over the existing app to retain data.

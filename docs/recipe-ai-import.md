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

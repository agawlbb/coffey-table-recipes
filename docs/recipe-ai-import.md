# Add recipe

The left navigation menu's Add recipe opens text/description, website, upload,
and camera options for the selected household. An online connection is required.
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

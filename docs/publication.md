# Open-source publication review

Prepared on 2026-10-12 with explicit authorization to back up and rewrite both
repositories' history, force-push cleaned references, and publish after review.

- License: GNU AGPL-3.0-only for original code, documentation and project rights
  in AI-generated icon, branding and category illustrations; see LICENSE and NOTICE.md.
- Personal account names, email addresses, local user paths and hosting account
  identifiers are sanitized in source and all published branches/tags. Commit
  identities use GitHub's public no-reply address. Private recovery bundles and
  original build logs/artifacts are stored outside both repositories.
- Historical Actions records are retired after their private ZIP backups pass
  integrity verification. Their original commit hashes must not be republished.
- Firebase settings, server/service-account secrets, personal imports, generated
  packages and Android/Apple signing material remain excluded from Git.
- Existing ID-based public recipe sharing and AI access remain unchanged.
- Administration uses the persisted role associated with a verified Firebase UID;
  personal email addresses no longer grant the role automatically.
- Backend pushes to main may deploy automatically. Hosted Flutter app updates
  still need explicit release/deployment authorization. Every macOS runner build
  requires separate explicit approval, including builds triggered by tag pushes.

Pre-publication validation: Flutter analysis clean; 13 administration/home widget
tests and seven iOS configuration/web deployment checks passed. Backend validation
includes 50 administrator checks, 51 authentication/household checks, 31 sharing
checks, six migration-checksum checks and 17 deployment/key-configuration tests.
Database tests used disposable local schemas, then the local database engine was
stopped. No AI model call, macOS build or hosted Flutter deployment was performed.

The initial pattern scan covered 779 historical text blobs and found no recognizable
provider API secrets or private keys. Publication requires a second scan of every
cleaned published ref and verification of remote visibility and deployment results.
Dependencies retain upstream licenses. Personal recipe source material and imported
publisher photographs are not covered by the project's license grant.

Existing clones must be replaced with fresh clones after the history rewrite.
Avoid merging old branches back into the cleaned history. Private backups are
for recovery only and must never be uploaded to a public repository.

## Clean-history verification

All 192 cleaned app/backend commits and 799 historical text blobs passed the
privacy-pattern scan and Gitleaks 8.30.1 with zero findings. Atomic leased pushes
replaced every published branch and tag; remote references matched the cleaned
local history. No private Codex recovery references were published.

GitHub still serves personal details through original detached commit IDs.
Both repositories remain private pending the user's choice of fresh public
repositories, a GitHub cache purge, or acceptance of that residual exposure.
History rewriting alone does not erase GitHub's cached objects.

The iOS workflow now starts only through manual dispatch after explicit approval;
version tag pushes cannot automatically start macOS jobs. Backend main deployment
remains automatic. Existing Actions records are privately backed up and remain
private. Their deletion requires explicit authorization; automatic approval review
rejected permanently deleting them without that additional authorization.

Backend deployment run 38264678428 was blocked before any step ran by GitHub's
billing/spending restriction. No hosted files were changed. The hosting browser
session also requires a fresh login. Existing repositories remain private and no
macOS run was started. Publication and deployment await resolution of these items.

## Fresh repository publication

On 2026-10-12 the user chose fresh public repositories containing only sanitized
history, retaining the original repositories and Actions records privately.
The public source destinations are agawlbb/coffey-table-recipes and
agawlbb/coffey-table-recipes-server. Only branches and tags are copied; private
recovery refs, original cached commits, and old build records are excluded.

Local origin will point to the new public repository, with private-history retaining
the old remote for recovery. Existing clones should use the new public URLs.
Firebase client build configuration may be transferred as an encrypted GitHub
secret without printing its contents. Hosting secrets cannot be read back from
GitHub; they must be supplied to the new repositories before hosting deployment.
Backend checks still run without them; automatic deployment activates when both
CPANEL_USER and CPANEL_API_TOKEN are configured. No AI access limits change.
All iOS builds remain manual and require explicit approval. Publication performs
no macOS build and no hosted Flutter update.

## AI access decision

The owner requested removal of the 20-import-requests-per-hour quota on 2026-10-12.
This is a separate authorized behavior change from repository publication.
Authentication and household authorization remain unchanged; SECURITY.md explains
why public source does not expose the API key or grant anonymous backend access.
Registration can occur through the app or Firebase APIs, so website visitation
is not an enforceable boundary. Backend validation exercised 25 successive imports
with an exhausted legacy counter and a fake upstream transport: all 77 recipe AI
checks passed without paid API calls. The hosted change awaits deployment credentials.

## Publication and hosted deployment verified

Completed on 2026-10-12. Fresh public repositories are
https://github.com/agawlbb/coffey-table-recipes and
https://github.com/agawlbb/coffey-table-recipes-server. Every copied branch/tag
passed privacy and Gitleaks checks. Anonymous lookups of original personal-data
commit IDs returned no commit found; none of the old Actions records were copied.
Original underscore-named repositories remain private and are archived to prevent
obsolete code deployment. Their existing records were retained without deletion.
Local origin uses the new public repository; private-history retains the original.

The user explicitly approved encrypted Firebase client build settings in the new
app repository and an expiring cPanel deployment token in both new repositories.
Only secret names and successful storage were verified; values were not printed
or committed. The new token expires October 12, 2027. Existing hosted OpenAI
credentials and user data were preserved. GitHub workflow tokens have read-only
default permissions, and main is protected against force pushes and deletion.

Public Ubuntu deployment run 38309357432 successfully deployed backend source
209024378e04f0e2a65c37fb4ab28883d8fe978f. PHP syntax, locked dependencies,
77 AI preprocessing/repeated-import checks, migration checks, sharing checks,
deployment tests, TLS and publish verification passed. Hosted backend-version.json
independently identifies that commit. Health returned 200, anonymous administrator
and AI requests returned 401, protected configuration returned 403, and the public
recipe page links to the new source. Administrator role lookup by Firebase UID and
removal of the hourly import limit are now deployed. No database migration was run.

Future backend main pushes deploy automatically. App website deployment still
requires explicit authorization and a version tag. No macOS workflow was dispatched,
no paid AI request was made, and the hosted Flutter app was not changed. The app's
Firebase build settings are ready for a separately approved future iOS build.

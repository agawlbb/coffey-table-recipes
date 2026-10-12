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
remains automatic. Existing Actions records are privately backed up and retired
before any publication.

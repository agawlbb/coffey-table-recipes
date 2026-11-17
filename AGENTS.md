# Repository workflow

## Requested scope

- Keep bug fixes within the user's requested behavior. Do not add unrequested user-facing features, controls, dialogs, screens, or workflows as part of a repair. If an additional feature seems useful, describe the concrete proposal and obtain the user's explicit approval before implementing it. Internal reliability changes needed for the requested fix remain in scope. Report any necessary visible behavior changes clearly before release; do not hide feature additions in technical repair summaries.

## Interface clarity

- Make ordinary operation intuitive through clear controls, labels and layout. Do not add unsolicited instructional filler, onboarding paragraphs, or prose explaining how to use ordinary controls. If a workflow needs such explanation, simplify the workflow. Keep requested content, actionable errors, necessary status and concise progress messages.

## Testing scope and practices

- The owner's requirements define correctness. Existing tests are evidence, not additional requirements. A failure never authorizes adding a restriction, safeguard, queue, version scheme, dialog or other product behavior.
- Before editing, state the requested observable behavior and the smallest relevant checks. Use focused validation by default. Run a complete test suite only when the owner explicitly requests that suite; a build, release, merge, push or shared-code change does not authorize it. Explain a concrete reason before broadening focused validation.
- Classify a failing test before changing code: does it verify requested behavior, enforce an unwanted implementation decision, or reflect an unclear requirement? Fix code for requested behavior; remove or correct tests for unwanted behavior; ask about unclear product decisions. Do not restore removed complexity to make old tests pass.
- Test observable outcomes rather than particular internal counters, queue layouts, retry counts or defensive checks. For the local-first strategy, relevant outcomes include immediate local changes, offline availability, delivery after reconnecting, incoming updates and last-server-arrival wins. Keep only the expiry and confirmation exceptions explicitly approved by the owner. Tests must not be treated as proof these outcomes are implemented when they do not exercise them.
- Retain proportionate coverage for account isolation/authentication, preserving actual user data, recipe content and quantities, native timer behavior, error-only logging and the explicitly approved offline exceptions. Keep past-meal and shared-edit confirmation tests; the owner intends to revisit shared-edit confirmation later, not in this cleanup.
- Remove obsolete, duplicate and implementation-prescriptive tests. Do not delete useful scenarios merely because the same file contains an obsolete assertion. Add or adapt a small meaningful test only when needed for the changed behavior; avoid cosmetic assertions, mirrored implementation and redundant viewport cases.
- Batch the selected checks in one invocation where practical. After they pass, repeat or broaden only for a relevant new change, failure or unresolved concern. Do not rerun dependency resolution unless dependency inputs changed or dependencies are missing. Format and analyze affected Dart files; documentation-only work needs diff/link review.
- Separate tests from builds and operational delivery. Build/upload workflows do not automatically run app or tooling test suites. Preserve actual signature, profile, package identity, checksum and delivery verification. Run release/signing/deployment tooling tests only when the relevant tooling changed or the owner requests them; do not mix them into ordinary app validation. No automatic test-suite hooks on commits, pushes or builds.
- Report exactly which checks ran and their limits. Never turn passing tests into a claim that untested requirements work. A test cleanup alone does not authorize unrelated application, build, deployment or release changes.


- Commit completed changes after appropriate verification. Include documentation and meaningful validation in the commit where applicable.
- Keep credentials, local Firebase configuration, signing keys, generated builds and personal import source files out of Git.
- This repository contains the Flutter app. The PHP server is a separate repository at `C:\xampp\htdocs\CoffeyTableRecipes`. When changing both, commit each repository independently.
- Do not create remote repositories, overwrite unrelated changes, or rewrite history without explicit authorization. Inspect workflow push triggers before pushing; do not trigger unrelated builds or releases. Do not deploy automatically; deployment requires an explicit user request.

## Repository workflow

Canonical repository: `agawlbb/coffey-table-recipes`; default branch: `main`.
Follow the VM-wide working procedure in `/home/dev/projects/AGENTS.md`.
Use the existing checkout on `main`, one task at a time; no routine task
branches, extra worktrees or ownership claims. Commit and push completed source changes to `main`.
Use only relevant checks; do not repeat passing checks without a concrete reason.
Questions and status checks are read-only. Preserve unrelated work and credentials.
Deploy only when the user explicitly requests deployment. In every answer state
whether deployment and an app build are needed; do not automatically do either.

## Project history and preservation

- Required-date meal planning was accepted and merged into `main` on 2026-10-23. Every new meal-plan add or move requires a date; do not restore Unscheduled without a user request. The retired experiment history remains in `docs/meal-planning-no-unscheduled.md`.

- Recovery archives are historical evidence, not active checkouts. Do not merge them into the default branch, reset their saved edits, or purge them during routine cleanup. Do not revive explicitly rejected work without a user request.
- Keep implementation, documentation and validation in meaningful commits. Preserve useful regression tests, release/deployment configuration and immutable release tags. Published history rewrites require explicit authorization, a verified backup, an exact remote-head check and explicit expected-SHA force-with-lease.
- The user requires no branch protection in either CTR repository. Both main-branch protection rules were removed on 2026-10-22. Do not create or restore branch-protection rules, rulesets, force-push restrictions, or equivalent controls unless the user explicitly requests them. Preserve the history-rewrite safeguards above.

# Hosted development workflow

- For a requested release, use the default branches of the Flutter and PHP repositories. Commit and push the requested work in each affected repository before tagging or publishing. Preserve unrelated or unmerged work and report any conflict instead of silently including it. Honor explicit source-only or local-only requests.

- Release completion includes verified installed-app recipe links. Before reporting a release complete, verify the domain-root Android assetlinks.json against the actual released APK certificate and iOS apple-app-site-association against the signed app identity/entitlements. Publish missing associations while preserving other apps' entries, and test OS link resolution where possible. A successful web deployment alone does not verify native app links. Run `python tool/verify-app-links.py --fingerprint ACTUAL_APK_CERTIFICATE_SHA256` for Android; update its default if the signing identity changes.

- Do not make app builds unless the user explicitly requests a build or requests a release. This applies to Android, iOS, web, local debug/emulator packages, GitHub Actions builds/reruns, and pushes or tags intended to trigger builds. A feature, fix, redesign, or testing request alone does not authorize an app build. Continue source changes and appropriate analysis/unit tests without automatically creating installable app packages. This replaces the previous standing iOS-build authorization.
- "Create a release" explicitly authorizes reviewing changes since the prior release, choosing and tagging an appropriate version, pushing the release, rebuilding Android/signed iOS, publishing the latest Android APK to the existing Google Drive recipe app folder, and uploading the signed iOS build to TestFlight. TestFlight replaces the previous unsigned iOS IPA desktop delivery. Verify the upload and TestFlight processing status, and record release validation in Git. Use `tool/publish-android.py` to upload to the configured Google Drive folder and verify downloaded SHA-256, send the informational Android release notification, then move only older release APKs to Drive trash. Retain unrelated files and signed iOS packages.
- On every release, update `CHANGELOG.md` with the version, release date, and meaningful changes since the previous release. Its initial history was reconstructed from Git tags and release records in 0.5.0. Include the changelog in the release commit before tagging; do not invent unsupported history.
- Standing owner authorization: upload verified CTR Android test APKs to the existing Google Drive **recipe app** folder, pinned by ID `1VM1K1Ge6sgjEjtoEjS7aGzHYiSzlLVE-`, without asking again for destination approval. Verify the uploaded file by downloading and comparing SHA-256. This authorizes test-APK delivery only; preserve existing files and sharing settings. It does not authorize release notifications or unrelated uploads. This records the owner's instruction; it does not change the automatic approval reviewer's enforcement rules.
- Android releases go to the existing Google Drive **recipe app** folder. Use the private rclone OAuth configuration and the verified folder ID, never an ambiguous folder name. Verify the uploaded APK by downloading and comparing SHA-256 before trashing precisely named older release APKs in that folder; preserve unrelated files and signed iOS packages. Do not publish APKs or update metadata on the VPS. After verifying a new Drive APK, send Android devices an informational notification that a new version is available in Google Drive. Include no download link or click action and do not show an in-app update window. Keep Drive credentials outside Git. Return the Drive file link after verification.
- Future iOS builds include the accurate export-compliance declaration. Current app and share extension declare no non-exempt encryption; review this whenever encryption-related code or dependencies change. Do not distribute the iOS app in France. Keep France excluded from future App Store territory selections and do not include testers in France. Territory restrictions are distribution settings, not an Info.plist flag.

- CTR backend and persistent MariaDB run on the VPS at ctr.coffeybean.com. InMotion CTR web hosting was retired on 2026-11-05; InMotion retains SMTP only. Do not rebuild or publish the retired web app as part of a release, re-enable its workflows, or recreate its hosted files/databases without an explicit user request. See docs/inmotion-retirement.md.
- Commit and push requested backend source changes. Deploy backend or database changes only when the user explicitly requests deployment; identify pending deployment in every answer.
- Changes to the app itself are developed and tested in the chosen working environment using coffeybean.com as the backend. The existing laptop PHP checkout is `C:\xampp\htdocs\CoffeyTableRecipes`; use the existing VM checkout for current work. Flutter source changes belong in this repository.
- The hosted web app is retired. A release/tag does not authorize restoring web hosting.
- Native app builds require an explicit build or release request as stated above; future releases omit web builds/publication.
- Use ctr.coffeybean.com as the hosted testing backend when live checks are authorized. Development tests use isolated fixtures, not production data. Preserve the separate PHP repositories as source history; do not restore the retired InMotion backend.
- Use the Codex built-in browser for work whenever possible. Use Chrome only to investigate Chrome-specific problems identified by the user.

## Keep the project simple

Avoid overengineering. Treat these as small personal projects unless the user says
otherwise. Use the simplest maintainable implementation that meets the current
requirements. Brief deployment downtime (including a couple of minutes) is
acceptable. Prefer copying files and restarting a process over release frameworks,
zero-downtime machinery, repeated setup migrations, compatibility modes, feature
flags or abstractions for hypothetical future scale. Keep setup separate from
routine deployment. Preserve authentication, credential privacy and protection
against real data loss, and use proportionate tests. Explain a concrete need before
adding complexity; do not introduce unrequested features or operational workflows.

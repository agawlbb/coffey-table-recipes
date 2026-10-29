# Repository workflow

## Requested scope

- Keep bug fixes within the user's requested behavior. Do not add unrequested user-facing features, controls, dialogs, screens, or workflows as part of a repair. If an additional feature seems useful, describe the concrete proposal and obtain the user's explicit approval before implementing it. Internal reliability changes needed for the requested fix remain in scope. Report any necessary visible behavior changes clearly before release; do not hide feature additions in technical repair summaries.

## Proportionate validation and coding speed

- Default to focused validation, not `flutter test` over the entire repository. Before editing, identify the changed behavior and the smallest relevant test files; include callers and shared dependencies when affected. Run them together in one Flutter invocation, for example `flutter test --no-pub test/recipe_filter_dialog_test.dart test/blank_recipe_detail_layout_test.dart` when dependencies are already resolved.
- Run the complete Flutter suite once for a release, an explicit full-suite request, or a cross-cutting change whose affected areas cannot reasonably be bounded (such as shared persistence, authentication, sync, routing, or dependency/SDK changes). A commit or push alone does not require the full suite. If coverage uncertainty warrants broadening checks, state the reason.
- Iterate with the failing or affected tests. After checks pass, do not repeat them unless subsequent edits affect their behavior or invalidate the result. Documentation-only follow-ups do not invalidate a passing code check. Record the commands and scope actually verified; never imply unrun tests passed.
- Documentation-only changes need diff/link review, not Flutter analysis or tests. For Dart changes, format changed files and analyze the affected files; broaden analysis when shared interfaces or dependencies change. Do not rerun dependency resolution unless dependency inputs changed or packages are missing.
- Add tests for meaningful behavior, regressions, boundary conditions, and failure paths. Do not add tests for trivial cosmetic changes, assertions that mirror implementation, or duplicate scenarios already covered. Prefer extending an existing relevant test. Retain distinct responsive breakpoints and accessibility coverage; avoid multiple near-identical viewport sizes without a specific regression reason.
- Keep release/signing/deployment tooling tests out of ordinary app validation unless those tools changed. Device/integration runs must add device-specific coverage; do not wrap existing mocked widget suites solely to run them again on a device. Builds still require explicit build/release authorization.
- Batch independent read-only inspections and relevant tests; avoid repeatedly scanning the entire repository, polling unchanged jobs, or running simultaneous Flutter commands against the same checkout. Use existing verification evidence when it matches the current source and scope. Do not introduce automatic builds or full-suite pre-commit/push hooks.


Complete and verify project work, commit it, and push it to the existing GitHub origin. Before declaring completion, verify a clean working tree and matching local/GitHub branch heads. Respect an explicit instruction to keep work local or avoid deployment; report any synchronization blocker instead of claiming completion.

- Commit completed changes after appropriate verification. Include documentation and meaningful validation in the commit where applicable.
- Keep credentials, local Firebase configuration, signing keys, generated builds and personal import source files out of Git.
- This repository contains the Flutter app. The PHP server is a separate repository at `C:\xampp\htdocs\CoffeyTableRecipes`. When changing both, commit each repository independently.
- Do not create remote repositories, overwrite unrelated changes, or rewrite history without explicit authorization. Inspect workflow push triggers before every push. A source push does not authorize a build or deployment.

## GitHub, branches and workspaces

- GitHub `agawlbb/coffey-table-recipes`, default branch `main`, is the canonical copy of accepted code and history. Laptop, VPS and cloud checkouts are working copies. The default branch is for integration of completed work, never a working branch for a task.
- Prefer the VPS for most development. Development may also take place on the laptop or another authorized environment, including emulator, webview and device testing. Independent tasks use separate, clearly named temporary branches and separate working directories (Git worktrees or clones). Do not share a writable checkout between concurrent tasks. There is no permanent designated chat owner or owner-chat approval requirement.
- Before editing, read applicable instructions and inspect current branches, worktrees, local edits, live GitHub heads and active writers/builds. Preserve unrelated and unpushed work; a clean tree alone does not prove inactivity. Coordinate overlapping changes and shared resources with the tasks involved.
- Before starting new work, fetch from GitHub (`git fetch origin`) and create the temporary task branch from the latest fetched remote default (`origin/<default>`, where `<default>` is this repository's `main`, `master` or `work` branch identified above). Record the task's purpose and base commit; do not branch from a stale local default.
- Before resuming existing work, fetch from GitHub and inspect the intended task branch, its upstream and any divergence from the remote task branch and canonical default. Reconcile updates intentionally without overwriting uncommitted, unpushed or unrelated changes. Preserve local work before switching branches or integrating updates, and resolve conflicts without discarding another task's work. Do not blindly run `git pull` in the current branch or pull another task's branch into it.
- To move the same task between machines, commit and push that task branch, then fetch and continue the intended branch on the other machine after coordinating the handoff and following the resumption checks above. Never overwrite another task's work or use recovery archives as active workspaces.
- Before merging, fetch and integrate the latest canonical default into the task branch, resolve conflicts without discarding others' changes, review the diff and rerun relevant checks against the integrated result. Serialize merges into the default branch and recheck its live head before publishing. Respect existing protections; do not bypass them or rewrite published history.
- Commit and push completed work to the existing GitHub origin, merge accepted work into `main`, and verify the remote commit and a clean task working tree before reporting completion. Report blockers or unsynchronized work explicitly. Inspect push triggers before every push; GitHub publication does not itself authorize builds, releases, deployment or installation.
- Temporary task branches must be removed both locally and remotely once their purpose is fulfilled and their changes are merged into the canonical default branch, or their work is explicitly abandoned by the user or the person responsible for that task. Verify the merge or abandonment decision first; preserve commit history, required recovery evidence and recoverable unique work before deletion. Stale or paused work is not abandoned. Never discard unmerged work without that decision, delete another task's branches, or purge recovery archives as routine cleanup.

## Project history and preservation

- Required-date meal planning was accepted and merged into `main` on 2026-10-23. Every new meal-plan add or move requires a date; do not restore Unscheduled without a user request. The retired experiment history remains in `docs/meal-planning-no-unscheduled.md`.

- Recovery archives are historical evidence, not active checkouts. Do not merge them into the default branch, reset their saved edits, or purge them during routine cleanup. Do not revive explicitly rejected work without a user request.
- Keep implementation, documentation and validation in meaningful commits. Preserve useful regression tests, release/deployment configuration and immutable release tags. Published history rewrites require explicit authorization, a verified backup, an exact remote-head check and explicit expected-SHA force-with-lease.
- The user requires no branch protection in either CTR repository. Both main-branch protection rules were removed on 2026-10-22. Do not create or restore branch-protection rules, rulesets, force-push restrictions, or equivalent controls unless the user explicitly requests them. Preserve the history-rewrite safeguards above.

# Hosted development workflow

- When the user requests a release, inspect local and GitHub branches in both repositories. If feature branches exist in addition to main in either repository, ask the user how to handle them before proceeding with the release. Do not assume they should be merged, excluded, or deleted.
- Before every release, commit all project work appropriate for Git and push all local branches and tags from both the Flutter and PHP repositories to their existing GitHub remotes, including work outside the release branch. A release request explicitly authorizes these pushes. Verify both repositories are synchronized before tagging or publishing the release. Preserve the exclusions for credentials, local configuration, generated builds, and personal files; do not force-push or rewrite history without explicit authorization.

- Release completion includes verified installed-app recipe links. Before reporting a release complete, verify the domain-root Android assetlinks.json against the actual released APK certificate and iOS apple-app-site-association against the signed app identity/entitlements. Publish missing associations while preserving other apps' entries, and test OS link resolution where possible. A successful web deployment alone does not verify native app links. Run `python tool/verify-app-links.py --fingerprint ACTUAL_APK_CERTIFICATE_SHA256` for Android; update its default if the signing identity changes.

- Do not make app builds unless the user explicitly requests a build or requests a release. This applies to Android, iOS, web, local debug/emulator packages, GitHub Actions builds/reruns, and pushes or tags intended to trigger builds. A feature, fix, redesign, or testing request alone does not authorize an app build. Continue source changes and appropriate analysis/unit tests without automatically creating installable app packages. This replaces the previous standing iOS-build authorization.
- "Create a release" explicitly authorizes reviewing changes since the prior release, choosing and tagging an appropriate version, pushing the release, rebuilding web/Android/signed iOS, publishing the hosted app, publishing the latest Android APK to the existing Google Drive recipe app folder, and uploading the signed iOS build to TestFlight. TestFlight replaces the previous unsigned iOS IPA desktop delivery. Verify the upload and TestFlight processing status, and record release validation in Git. Use `tool/publish-android.py` to upload to the configured Google Drive folder and verify downloaded SHA-256, send the informational Android release notification, then move only older release APKs to Drive trash. Retain unrelated files and signed iOS packages.
- On every release, update `CHANGELOG.md` with the version, release date, and meaningful changes since the previous release. Its initial history was reconstructed from Git tags and release records in 0.5.0. Include the changelog in the release commit before tagging; do not invent unsupported history.
- Android releases go to the existing Google Drive **recipe app** folder. Use the private rclone OAuth configuration and the verified folder ID, never an ambiguous folder name. Verify the uploaded APK by downloading and comparing SHA-256 before trashing precisely named older release APKs in that folder; preserve unrelated files and signed iOS packages. Do not publish APKs or update metadata on the VPS. After verifying a new Drive APK, send Android devices an informational notification that a new version is available in Google Drive. Include no download link or click action and do not show an in-app update window. Keep Drive credentials outside Git. Return the Drive file link after verification.
- Future iOS builds include the accurate export-compliance declaration. Current app and share extension declare no non-exempt encryption; review this whenever encryption-related code or dependencies change. Do not distribute the iOS app in France. Keep France excluded from future App Store territory selections and do not include testers in France. Territory restrictions are distribution settings, not an Info.plist flag.

- Unless the user specifies otherwise, all changes to database data, database structure, and the backend hosting process occur on the hosted coffeybean.com site.
- Deploying and pushing changes to the hosted backend and database are authorized without additional permission within the requested work, including Git pushes needed for backend deployment.
- Changes to the app itself are developed and tested in the chosen working environment using coffeybean.com as the backend. The existing laptop PHP checkout is `C:\xampp\htdocs\CoffeyTableRecipes`; other isolated working copies are permitted. Flutter source changes belong in this repository.
- Update the hosted app only when the user explicitly asks and a new version is tagged. A tag alone does not authorize deployment.
- Outside an instruction to "create a release", obtain explicit permission before pushing or deploying the hosted app. An instruction to "create a release" authorizes hosted app deployment. App builds require an explicit build or release request as stated above.
- Use coffeybean.com as the testing backend. Retain the local PHP source for development. The backend and persistent MySQL database are hosted exclusively; the outdated local recipe database was retired on 2026-10-11.
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

# Required meal dates: accepted experiment history

Historical record: named chats, checkout ownership and branch locations below describe past work, not current workflow requirements. Follow [AGENTS.md](../AGENTS.md) for GitHub-canonical development, task coordination, merging and branch cleanup.

Status: accepted and merged into `codex/meal-planning-v2`, 2026-10-23. Separate local/remote experiment branches retired at the user's request.

Owner: Plan CTR meal planning v2 chat (`01a165dd-0324-7e10-8ffc-03bb397420bc`).
Original branch: `codex/meal-planning-no-unscheduled` (retired after acceptance).
Parent: `codex/meal-planning-v2`.
Base: `1fc86e003a2e54ebf6f0f5121a4f1409f7c1f312`.

The experiment was created separately so it could be abandoned. The user has now accepted it; maintain the required-date implementation on the regular meal-planning feature branch. Original setup and build records below are historical evidence.

## Original planning questions (resolved below)

- What happens when Add to meal plan is used from normal recipe browsing or recipe detail, where no date has been chosen?
- What happens when a recipe is tapped in the planner's wide-screen recipe browser, rather than dragged onto a date?
- How should existing Unscheduled entries be handled without silently deleting household data?
- How does date selection combine with variation confirmation and paired-dish suggestions?

Existing dated-meal behavior remains the baseline: drag between dates, trash drop target, past-date confirmation, household sharing and history. These questions record planning topics, not approved behavior.

## Setup validation

The canonical checkout was clean, parent local and GitHub heads matched the base, and the coordinating owner confirmed no active writers or builds. Workflow inspection found only manual workflow_dispatch triggers. This commit changes ownership/planning documentation only; no app tests or builds are needed for setup.


## Updated baseline (2026-10-23)
Merged all updates from `codex/meal-planning-v2` through `f3b9ec894a4817cc706a2969b1286ec385e8f811`, including current main integration, local database/sync changes and planner fixes. Original branch creation base above is retained as historical context. Unscheduled remains implemented until the alternative is planned and the user requests implementation.

Merge validation: no conflicts; application/platform sources, dependencies and tests exactly match the incoming feature branch, whose last full validation passed 458 Flutter tests with clean analysis. Only experiment ownership/planning documentation differs. No repeat test run, app build, backend change or deployment was needed for this identical application tree. The canonical checkout remains on this experiment branch.


## Approved implementation (2026-10-23)
User approved removing Unscheduled and explicitly stated there are no existing unscheduled meals to migrate. All normal-browser, regular/blank viewer and wide planner browser additions select a recipe version if needed, then a date. The date chooser lists household today plus six following days with weekday/date, followed by Another date opening the calendar. Cancel adds nothing. A dated planner Add and direct drag-to-date retain their date; placeholders remain dated. Past-date confirmation and initial-add pairing suggestions remain; moving between dates never offers pairings.

Unscheduled section and its add controls are removed. LocalData rejects add/move operations lacking a valid supported calendar date before queuing or sending anything, including review/reapply operations. No migration or shared backend validation change is introduced, keeping the regular feature branch as a reversible comparison. User explicitly authorized local XAMPP web and Android debug APK builds from this experiment; no hosted Flutter publication is included.

Implementation validation: full Flutter suite passed (463 tests), flutter analyze --no-pub clean. Coverage includes household week labels, cancellation, calendar/past-date confirmation, normal-browser pairing additions on the selected date, desktop selection, blank/regular viewers, retained dated picker/placeholder/drag flows, and rejection of missing/invalid dates before durable queue writes. No existing-data migration is required per the user.


## Test builds (2026-10-23)
Built clean experiment source `53aac95cf09bf84061d7594a61a7dbb5d3baab50` (1.8.5/build29) after 463 passing tests and clean analysis.

- Web command: `flutter build web --no-pub --base-href=/CoffeyTableRecipes/app/ --dart-define-from-file=config/firebase.local.json`, then `tool/prepare-web.py`. Copied assets only into ignored local XAMPP app/. `http://localhost/CoffeyTableRecipes/app/` serves the exact source version metadata, bootstrap and font manifest. Served main.dart.js bytes match the build, SHA-256 `2fc959a5207fac846708144aee1cf6be0e27a79ed54f6a80d9b0eab8340605fe`.
- Android command: `flutter build apk --debug --no-pub --dart-define-from-file=config/firebase.local.json`. Delivered `G:/My Drive/recipe app/CoffeyTableRecipes-no-unscheduled-test-53aac95.apk` (199,907,647 bytes). Source and delivered SHA-256 match: `d14a5ecad181653935933dcb55d42dd5ac0c50835fe8d2c1090cae26cf9c0012`. APK v2 signature verifies with existing Android Debug certificate SHA-256 `f8de933f14b9bb4b3191a94aedc8637972c5ab224565f6abd7808f8038d12097`; package `com.coffeytable.coffey_table_recipes`, version 1.8.5/build29, debuggable.

Both builds succeeded; existing plugin compatibility warnings remain. No device installation, release/tag, backend source/data change or hosted Flutter publication performed. Parent feature/main and previous artifacts retained. The backend working tree remains clean; generated local app assets are ignored. This subsequent documentation commit records delivery without changing built source.


## Acceptance and branch retirement (2026-10-23)
The user accepted the no-Unscheduled behavior and requested merging all experiment work into the regular feature and removing the separate local/GitHub branch. Accepted tip `b9a1831809b2497e82007a7974fbe139eefe47b7` is retained as an ancestor of the regular feature. Application/platform/dependency/test trees match the accepted tip exactly; its 463 passing tests, clean analysis and verified local web/Android builds remain applicable. Only ownership/current documentation changed during integration, so no repeat app tests or rebuild were necessary. The existing local web and APK remain valid tests of the accepted implementation. Main and backend are unchanged.

# Meal planning without Unscheduled: experiment

Status: implemented on the experimental branch, 2026-10-23.

Owner: Plan CTR meal planning v2 chat (`01a165dd-0324-7e10-8ffc-03bb397420bc`).
Branch: `codex/meal-planning-no-unscheduled`.
Parent: `codex/meal-planning-v2`.
Base: `1fc86e003a2e54ebf6f0f5121a4f1409f7c1f312`.

The user wants to explore eliminating Unscheduled meals on a separate branch so the experiment can be abandoned. Keep the parent branch intact. Plan the behavior with the user before implementing it. No builds, deployment, backend or persistent-data changes are part of this setup.

## Decisions to plan

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

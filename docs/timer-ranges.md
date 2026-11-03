# Recipe timer ranges — 2026-11-03

App task `task/timer-ranges` starts at fetched main
`0f3b822afe3a6677f2ba231eaec9ac911f262d3f`. Backend companion
`agawlbb/coffey-table-recipes-vps` uses the same branch name, base
`c28b633f7b46faedc9547e218f0f814417b40ed3`.

Development worktrees are `build/timer-ranges` and `build/timer-ranges-vps` under
`/home/debian/projects/coffey-table-recipes`, separate from the running
`task/cooking-sessions` worktrees. Cooking sessions overlaps native timers,
cooking mode and synchronization; integration must preserve both tasks. This task
did not edit, merge or deploy that task's work.

Timed actions retain `duration_seconds` as their minimum and optional
`duration_max_seconds` as their maximum. Editor validation and backend validation
require maximum >= minimum. Details, editor previews and cooking mode display the
range. Starting uses the minimum. At expiry the app offers the remaining time,
including in the global bar when another page is open. After accepting, extension
metadata is zero and cannot be offered again. Stopping dismisses the range.
Changing a timer manually clears its extension. Permission/scheduling failures
retain the previous timer and its unused extension.

Native Android/iOS records and timer synchronization preserve extension metadata.
Existing revision checks and server-side consumption reject a competing second
extension; successful retries keep the same result. Expired ranges can be restored
without replaying an alarm. Native alarm/notification behavior was source-reviewed;
no packages were built, installed or tested on physical devices. The extension is
selected in the app, not a new operating-system notification action.

Imports encode “3 to 5 minutes” and “cook 3 minutes, check, add up to 2 minutes” as
one timer with minimum 180 and maximum 300 seconds. Fractional hours are retained.
Separate stages, estimated timings and unbounded continuations are not combined.
Chat, clarification, variation and normal save paths preserve the range fields.

## Hosted inventory

Surveyed all 69 active recipes: 526 steps and 188 existing actions. Reviewed 66
candidate ranges. Excluded a reviewer anecdote and an early-check offset. Updated
62 existing timers and added 2 missing range timers across 30 recipes. Eight
existing midpoint timers now start at the instruction's stated minimum. Original
instructions, labels and unrelated action fields were preserved; each changed
recipe revision advanced once. A fresh survey proposed zero further corrections.

Private original snapshots, schema definitions, the reviewed plan and post-update
inventory remain outside Git in the backend state maintenance directory. Updates
used complete snapshot/revision checks and one transaction with range readback and
preservation verification. The backend companion's `TIMER-RANGES.md` records the
maintenance and validation details. No ongoing maintenance system was added.

## Source validation

Changed Dart files formatted; affected-file analysis and diff checks passed.
Focused validation covers 102 distinct Flutter tests:

- `flutter test --no-pub --concurrency=1 --reporter expanded test/timer_visibility_preview_test.dart test/cooking_mode_test.dart test/recipe_timer_navigation_test.dart test/sharing_timers_test.dart`: 19 passed.
- `flutter test --no-pub --concurrency=1 --reporter expanded test/recipe_time_test.dart test/timer_sync_test.dart test/recipe_import_test.dart test/recipe_chat_test.dart test/recipe_variation_test.dart`: 66 passed.
- All 17 `test/recipe_editor_test.dart` tests passed in the initial combined run,
  including range save preservation, duration editing and narrow-phone layout.
  That command also included the other nine files above. An initial stop-error
  wording regression was fixed and its whole timer file rerun in the 19-test group.
  The combined run later stalled while loading cooking tests with the shared
  container reporting OOM kills; its remaining Flutter tool was stopped. It is
  not counted as a passing combined command. Smaller completed groups are above.

Backend: 299 import checks, 37 working-draft checks, 60 chat checks, 92 variation
checks, timer/replay and database-inventory fixtures, save/load validation and
5 real WebSocket tests passed using disposable SQLite and mocked providers.
No live AI request, full Flutter suite, main integration, app build, release or
hosted Flutter deployment was performed. Source remains on task branches pending
explicit main-integration approval and a separately authorized app build/release.

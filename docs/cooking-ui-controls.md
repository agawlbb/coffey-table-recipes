# Cooking and shopping controls

Task `task/cooking-ui-controls`, based on canonical app main
`ae24bd3` (2.7.0). No version, tag, build or hosted Flutter deployment changes.

- The account, recipe viewer and cooking headers use the same live household
  socket state for the existing green connected icon. Disconnects hide it;
  account disposal clears the state.
- Stop closes the running-timers sheet after local cancellation succeeds, even
  when another timer remains. A cancellation failure keeps the sheet open.
- Shopping photo deletion appears only in the opened viewer. It uses the
  existing shopping-list write/sync path, preserves the item and its fields,
  and closes after a successful save. Failures keep the viewer open for retry.
  Child mode remains read-only. The former inline Remove photo button is gone.
- Cooking keeps the recipe title and Keep screen awake switch fixed above the
  progress line; steps and the existing end control scroll below it. The
  completed-step count line is removed. First-unchecked-step positioning and
  remote-update scroll preservation remain covered.
- Swiping either direction on a menu session ends it. No confirmation is needed
  for zero/all steps complete with no uncanceled timers. Other cases ask
  “End cooking session?” (Cancel/End); timers add
  “Running timers will be canceled.” Expired, undismissed alarms count as timers.
  Failed end commands leave the menu entry available.

The companion VPS branch `task/cooking-session-swipe`, based on `adc5d60`, allows
an accessible session to be ended without joining the current device. Other
cooking mutations still require a joined device; existing membership/invitation
checks continue to apply. Ending uses existing cancellation and broadcast/push.

Validation:

- Formatted changed Dart source/tests; analyzed the changed Dart files.
- Focused Flutter run: cooking_mode_test, cooking_sessions_test,
  recipe_menu_navigation_test, shopping_list_photo_test,
  timer_visibility_preview_test, shopping_list_retry_test, account_timer_menu_test.
  Initially one new photo test needed the existing row double-tap recognition
  timeout before asserting navigation. The corrected photo suite passed all six
  tests; all other files passed. No production timing was changed for that test.
- Final timer-sheet check (including another running timer), blank recipe layouts
  and home/account design: 19 tests passed together.
- Companion PHP cooking-session authorization/cancellation tests, data socket
  tests and source syntax check passed.

No complete Flutter suite, native build, release or physical-device check was
requested or performed for this task. App integration into main remains pending.

Companion backend source `bf7cf2e` is deployed on the hosted VPS. Service readiness,
public health and deployed-source hash verification passed; no database changes
were needed. Backend deployment does not publish the Flutter app changes.

## Signed Android test APK — 2026-11-03

The separately requested test build uses immutable source
`6185a5b74c772f8f3250f61fc2996389b2dac9ac`.
[Workflow 41619608261](https://github.com/agawlbb/coffey-table-recipes/actions/runs/41619608261)
passed native compilation, original signing identity, package/version checks,
timer-preference JNI checks and hosted app links. Independent `apksigner`,
`aapt` and actual-certificate association checks passed after download.

- Version `2.7.0-account-test`, build **55**, package
  `com.coffeytable.coffey_table_recipes`.
- Delivered filename: `CoffeyTableRecipes-2.7.0-cooking-controls-test-build55.apk`.
- APK SHA-256: `f226f06f3295b61cd56cfd9ad713a0c0f854c9de6092d875bdc3dd34930b3e59`.
- Certificate SHA-256: `f8de933f14b9bb4b3191a94aedc8637972c5ab224565f6abd7808f8038d12097`.
- [Verified Drive test APK](https://drive.google.com/file/d/1XfqayColS9H5p7TfJIQTW9cgf77TqAc6/view).
  Downloaded Drive bytes matched the APK SHA-256. Existing files were retained;
  no release notification was sent.

The source version is unchanged; the existing workflow supplied the test
version/build override. No release tag, main integration, web deployment or
iOS build was performed. Physical-device checks remain for this test package.

## Accepted completion and 2.7.1 preparation — 2026-11-03

The user accepted this work and requested main integration, temporary-worktree
cleanup and a three-platform release. Version 2.7.1/build 56 includes the controls
above and a correction for ending the displayed session: clear the cooking,
recipe-detail and overlay routes, select Recipes and show the recipe browser.
Ending a covered session removes that route without interrupting the active
screen. Ensure a frame is scheduled even when only session data changed.

Full analysis passed. The 20 focused cooking-session/navigation tests passed,
including local end, remote end, expiry, a timer dialog, an open drawer on the
real account screen, and ending a covered session. The full release suite and
platform delivery evidence are recorded separately after completion.

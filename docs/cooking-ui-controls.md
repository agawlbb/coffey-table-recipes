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

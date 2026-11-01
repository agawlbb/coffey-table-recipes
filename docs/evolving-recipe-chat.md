# Evolving recipe chat

Task branch: `feature/evolving-recipe-chat`, based on fetched app main
`9c840e26b3b61bbdcb7f0938986e6bcb3d006f6c`. Companion VPS branch uses the same
name and starts at `b8c0b24f9c04981f1604f52ddc13244b9a3007e2`.
User requested implementation with no main merge until explicitly instructed.

Chat and Working recipe tabs give each view the available phone/tablet space.
Chat keeps its scroll controller and unsent input while switching views. The
working recipe is readable plain text with ingredients and numbered steps.
View changes opens the recipe tab; added/replaced lines are highlighted relative
to the previous draft (removed lines disappear). Review/Save are unchanged.

Every request sends `draft_view: true`; responses carry authoritative server-held
`recipe_text` separately from concise conversational `message`. The companion
backend is required before publishing this client. It preserves inline recipe
replies for already released apps which do not send this field. This is needed
for the existing installed clients, not a separate feature flag.

The cooking prompt favors updating the unsaved working recipe even for “what
would happen if” and “tell me what adjustments to make.” It explains the effects
without another confirmation. Explicit explanation-only requests and unresolved
comparisons leave the draft unchanged. The server supplies current/previous
drafts for conversational undo; preference learning remains separate. No recipe
is persisted until the existing editor Save.

The composer uses keyboard Send, hardware Enter and Shift+Enter for a newline.
IME composition is not submitted. Existing single-flight/retry handling prevents
duplicate requests and preserves failed input. Scaffold resizes for reported
keyboard insets. Send leaves room for the app's floating keyboard-dismiss button.
When an iOS input is focused, at least 64 logical pixels are reserved above the
bottom for the Bluetooth suggestion/accessory bar, including when iOS reports
no or only a small inset; a full keyboard does not get double padding. This is
a conservative layout allowance, not native keyboard-frame detection.

Validation (2026-11-01): 34 tests passed with
`flutter test --no-pub test/recipe_chat_test.dart test/recipe_import_methods_test.dart test/recipe_variation_test.dart`.
Affected Dart analysis reported no issues; changed Dart files were formatted. Simulated layouts cover phone,
compact enlarged text, iPad landscape, and Bluetooth accessory bars with zero
and small reported insets, including sending and the ready-to-review state.
Tests also cover keyboard actions, IME composition, failed-send retention, tab
switching, highlighting, and existing review/save safeguards.
No physical iPhone/iPad or Bluetooth keyboard was available; actual OS accessory
behavior still needs device verification. No app builds, release, deployment,
main merge, database changes or live paid AI calls are included.


## Authorized backend deployment and Android test build

The user requested deploying this branch's VPS backend and a test Android APK,
without main integration. Backend source is `f31481216d1a75a833ca127a37567f4b1cdade79`.
The existing signed Android workflow adds one to the pubspec build for tests.
Reserve base build 48 here so the resulting test APK is build 49, newer than
the previously delivered test build 48. The workflow retains its existing
`2.5.0-account-test` version label. This is not a release or a main merge.

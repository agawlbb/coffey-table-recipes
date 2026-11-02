# Direct save from recipe chat — 2026-11-01

Branch feature/chat-direct-save starts at fetched main 9c840e2 and intentionally
integrates the combined Android-test branch 72b903a. Accepted shopping photos
remain intact. This task does not merge any feature into main or create an APK.

Remove View changes: Draft recipe already provides the recipe view. Replace
Review and save with Save. The existing local prepare request assembles the
agreed draft; the client then makes the normal recipe save request directly,
without opening RecipeEditor or requesting more AI. Existing recipes still offer
variation versus edit at Save. Shared edits retain their existing confirmation.

An uncertain save is retried with the same immutable body/client_save_id, keeping
the chat locked until recovered. A definite validation rejection permits further
chat corrections. New AI dishes open RecipeDetail from Add recipe; existing
recipe chats reuse their caller's existing viewer navigation for variations and
edits. Errors and progress remain in chat. No instructional filler is added.

Paired VPS branch strengthens holistic cooking evaluation for both direct and
hypothetical requests and copies the original cover into variations without AI.
See CHAT-DIRECT-SAVE.md there for backend validation and synthetic live examples.

Validation: all 32 recipe_chat_test.dart tests passed, including copied-photo
submission, lost-save response/receipt reuse, shared-edit confirmation, direct
create/variation viewer navigation, missing-field guidance and keyboard layouts.
All 20 recipe_import_test.dart and four account_timer_menu_test.dart scenarios
passed in the preceding combined run; its only failure was the new shared-edit
case, fixed by keeping the saving spinner hidden while awaiting confirmation.
Changed-file analysis and formatting passed. No full-suite claim.

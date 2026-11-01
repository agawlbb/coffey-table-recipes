# Chat review and save repair

Task branch `feature/chat-review-save` starts from app main
`9c840e26b3b61bbdcb7f0938986e6bcb3d006f6c`, then intentionally includes
`feature/evolving-recipe-chat` through `a5d5c1ed2597b2f2d4bbad7c363afc18a4724b99`.
The companion VPS branch starts from main `b8c0b24f9c04981f1604f52ddc13244b9a3007e2`
and includes deployed database chat context through
`9cb457dd9776f228f8789c617268bc55416a9d78`. Neither main is changed.

Review and save is available on both tabs whenever a working recipe exists. AI
readiness no longer hides this action. Busy, offline, unsent input and uncertain
message-retry guards remain. Reviewing an existing recipe asks whether to save
a new variation or update the existing recipe; the chat starts with neither
destination selected by the user. The chosen outcome is sent only on preparation.
Actual storage still requires the editor Save. Cancelling the choice keeps the
chat/draft and performs no preparation. Failed preparation retries its existing
turn/destination directly, without asking the user to choose again.

An animated indicator and live progress text appear outside tab content during
preparation. Preparation errors are also visible on either tab. The backend
preserves the draft and translates import-oriented failure guidance into a
message explaining the draft is retained and review can be retried.

The reported error is emitted by the shared standardizer for a non-completed
provider response. Its historical response envelope was not retained, so the
precise original incomplete reason cannot be established retrospectively. Chat
review now uses a lighter reasoning pass and more output space, with exactly one
retry only when the provider explicitly reports output-token exhaustion. Partial
JSON is never accepted. This still needs a formatting AI call to convert the
plain text working draft into editor ingredients, steps and timer actions.

Validation (2026-11-01): 37 tests passed using
`flutter test --no-pub test/recipe_chat_test.dart test/recipe_import_methods_test.dart test/recipe_variation_test.dart`.
Changed Dart files were formatted and analyzed. Backend checks include 126 chat,
294 recipe extraction, 92 variation, 66 context checks and 14 real-socket AI tests
with disposable SQL/fake providers. One live synthetic recipe probe with the
existing authorized credential returned completed structured ingredients/steps
in 4.1 seconds (not a timing guarantee). No production recipes or provider output
were logged by that probe. No app build, release or main merge is authorized by
this repair. Physical iOS/Bluetooth keyboard checks remain pending.


Backend preparation/error repair source `8df3346` was deployed and verified
healthy on 2026-11-01. Existing installed clients retain their fixed-mode
protocol. These app UI changes are committed on the feature branch but require
a new authorized app build before they appear on a device. No build was made
for this repair. Both repositories remain unmerged.

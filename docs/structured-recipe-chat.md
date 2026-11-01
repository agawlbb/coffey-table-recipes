# Structured working recipe chat

Task `feature/structured-recipe-chat` starts from fetched app main
`9c840e26b3b61bbdcb7f0938986e6bcb3d006f6c`, preserving the earlier review/save
feature through `155faa4652d8ce12c6c8893cf8dc78aa381194dd`. The VPS companion
branch starts from main `b8c0b24f9c04981f1604f52ddc13244b9a3007e2` and preserves
deployed chat/SQL context through `98a82fa60f1838e282e3eaca058bf6c5dd15b076`.
No main merge is authorized.

AI now returns concise prose and validated changes to one server-held structured
working recipe. It no longer repeats complete recipe drafts on every turn. The
server supplies only the current recipe, a bounded recent conversation and scoped
preferences; undo uses server snapshots. The full local human transcript remains
available. Review validates and opens editor data locally with no new AI call.
The existing prepare request remains to check live access and original revision;
there is still a network round trip, not another AI generation.

The app requires the structured working_recipe response and shows a brief
Opening recipe for review indicator. When local validation needs essential
information, it returns to Chat and shows only the missing fields. Review/save
destination, retry identity and editor Save remain as previously implemented.
New variations omit automatic original-photo copying to avoid delaying review;
edits retain their photos. Existing editor photo controls remain available.

The VPS keeps private per-operation token/call/timing metrics and a CLI report.
A real synthetic three-turn session used 508/178/51 output tokens for creation,
a targeted edit, and exact server undo. Review used zero AI calls/tokens and
about 6 ms server processing; real network/device latency is additional. No
historical full-session token baseline exists, so there is no claimed percentage
saving. Older text-only sessions may need one conversion before subsequent
reviews become local; original caches are retained.

2026-11-01 validation: 39 focused Flutter tests passed via
`flutter test --no-pub test/recipe_chat_test.dart test/recipe_import_methods_test.dart test/recipe_variation_test.dart`.
Changed Dart files were formatted; focused analysis found no issues. Backend
working document, patch atomicity, quantities/actions, undo, schema/identity
protection, history/preference bounds, legacy recovery and actual token accounting
have focused PHP and real-socket coverage. Live provider testing used only a
synthetic recipe and no production recipe/context. No app build, release, web
deployment or main integration is part of this feature implementation.

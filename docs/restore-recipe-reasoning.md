# Restore recipe conversation — 2026-11-01

Branch feature/restore-recipe-reasoning starts at fetched main 9c840e2 and
intentionally integrates feature/structured-recipe-chat f83c67a, retaining
its UI cleanup, SQL-context client compatibility and local draft review.

Rename the separate recipe tab to Draft recipe. Retain the existing chat/editor
flow and no instructional filler. The paired VPS branch restores original
cooking/context instructions, model reasoning defaults and full history/context;
complete editor-ready drafts replace patches. Review imports the agreed draft
without another AI request. See VPS RESTORE-RECIPE-REASONING.md for details.

Validated changed-file Dart formatting and analysis, and all 30 tests in
recipe_chat_test.dart (including phone/iPad keyboards, review choice and retries).
No build/release or main integration performed. Existing Android build 50 can
use the backend changes but does not contain the tab rename or prior UI cleanup.

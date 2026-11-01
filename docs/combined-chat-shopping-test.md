# Combined Android test — 2026-11-01

Temporary test/chat-and-shopping-photos branch from fetched main 9c840e2,
combining feature/restore-recipe-reasoning d0b052c and
feature/shopping-item-photo 3a3d495. Original branches and main remain intact.

Test build 51 (2.5.0-account-test) includes the restored recipe conversation,
Draft recipe tab and current chat cleanup, plus shopping item photo attachment,
replacement, removal and viewing. Native camera and clipboard need device testing.
The paired VPS test branch combines both backends; no InMotion deployment.

Validation: all 104 tests across recipe_chat_test.dart,
shopping_list_photo_test.dart, shopping_list_cache_test.dart,
local_data_test.dart and shopping_list_test.dart passed with concurrency 1.
An earlier run was interrupted to reduce memory pressure and is not counted.
No full-suite claim; existing invitation-label failure on main remains unrelated.

Build uses the existing manually dispatched Android workflow and signing
identity. Test package goes to the existing Drive recipe app folder, verified
by downloaded SHA-256. No release tag, automatic update notification or removal
of older packages. Main integration remains pending explicit acceptance.

Delivery verified:

- Source e1359c7aefd23856a88a3ee556be1e69b8029593; Android workflow
  https://github.com/agawlbb/coffey-table-recipes/actions/runs/41341347214 passed.
- Version 2.5.0-account-test, build 51; existing certificate
  f8de933f14b9bb4b3191a94aedc8637972c5ab224565f6abd7808f8038d12097.
- Signing/package/provenance, JNI and hosted Android app links passed workflow checks.
- SHA-256 035ad468c59b48702fda3a41292e6ffe40f22ac60f49273f86aa9338bc112f2a
  matched the downloaded Drive upload.
- https://drive.google.com/file/d/1660oAEifJ9CfOgdYWugOdzFXggU5XJXR/view
- Combined affected-file analysis passed (nine Dart files).
- Paired VPS source 7541c5a deployed and smoke checked, recorded at f305221.
- Main untouched; both features remain unmerged. No prior APK removal or notifications.

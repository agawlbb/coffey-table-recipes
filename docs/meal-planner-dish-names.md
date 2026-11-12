# Meal planner dish names

Task branch `fix/meal-planner-dish-names`, based on `origin/main`
`3aee285c64e14b7460f68f8df736d291112cbe0c`.

Recipe tiles now display dish names beneath their photos using the existing
word-wrapped caption. Previously only non-recipe entries displayed captions.
The duplicate photo tooltip was removed; the caption retains the full-name
tooltip and semantics. No backend changes are needed.

Focused validation: Dart formatting and analysis of `lib/src/meal_planner.dart`
and `test/meal_planner_test.dart`; all 32 tests across `meal_planner_test.dart`,
`meal_plan_dish_title_test.dart`, and `meal_planner_drag_stop_test.dart` passed.
No full suite was run.

## Requested Android test APK — 2026-11-12

Built locally inside the VM development container from immutable source
`62e4e874e090a0392dec45d23001406c004ca6b1`. Version
`2.10.1-meal-planner-test`, build 75; package
`com.coffeytable.coffey_table_recipes`, non-debuggable.

[Verified test APK](https://drive.google.com/file/d/12TfZJdwRsFxZBXGbN2lpgtweBLiyKDz0/view)
— `CoffeyTableRecipes-2.10.1-meal-planner-test-build75.apk`, 71,874,201 bytes.

SHA-256: `efd48b92c4cc9bd1931660a746b2cb840a9c90d4b6e07ee3857d99880b6bbf3f`.
Original signing certificate SHA-256:
`f8de933f14b9bb4b3191a94aedc8637972c5ab224565f6abd7808f8038d12097`.

APK signature, package/version, non-debuggable status, required native timer
Kotlin classes and hosted Android app links passed verification. Uploaded to the
existing pinned recipe app Drive folder; downloaded bytes matched SHA-256 and
byte comparison. Existing files and sharing were preserved. Physical-device
installation and visual acceptance remain untested.

The first two build attempts failed because `--no-pub` retained integration-test
plugin registration. The successful build used the existing workflow's
build-time pub registration regeneration. Dependency versions and tracked
source remained unchanged. This test delivery performed no release notification, release tag, iOS build,
backend deployment or main integration. The owner subsequently approved main
integration and release 2.10.2; see [release delivery](releases.md#2102--build-76--2026-11-12).

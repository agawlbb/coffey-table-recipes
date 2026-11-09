# Android layout test APK — 2026-11-09

The owner requested an Android test APK containing the five changes from this
conversation. Test branch `test/android-layout-updates` combines the completed
task branches from canonical base `c2139c8` without integrating into main:

- `0ea9f3e`: compact Timeline and Add dish buttons at each planner date's top right.
- `6f61e9a`: combine identical planner shopping ingredients and split conjunctions.
- `3e5f9af`: remove recipe-picture captions in the meal planner.
- `919b660`: place Error log and Dinner time under This device in Settings.
- `fea2176`: simplify the recipe-detail actions and show the full title in the page.

Immutable app source: `a95a8e1e988c1f0f55626e68bb3c3e069d817620`.
[Android workflow](https://github.com/agawlbb/coffey-table-recipes/actions/runs/42546233374)
uses the existing signed test-build mode: `2.9.0-account-test`, build 70.
The source pubspec version remains `2.9.0+69`.

## Source validation

Focused analysis passed for the four changed app files and the overlapping planner
and child-mode test files. All 35 tests passed in `meal_planner_test.dart`,
`meal_plan_ingredient_review_test.dart`, and `recipe_detail_layout_test.dart` on
the combined source. These cover planner layout and interactions, combined shopping
ingredients, and recipe-detail layout/shopping selection at phone and tablet widths.
The individual task commits record their additional focused validation.

Two existing failures from recipe-layout validation were reproduced with unchanged
main app source: the cooking navigation scenario in `recipe_menu_navigation_test.dart`
and the obsolete offline restriction scenario in `recipe_trash_test.dart`. They were
not repaired as part of the layout work. Passing layout tests do not establish actual
native alarm delivery or device acceptance.

## Delivery

[Download the verified test APK](https://drive.google.com/file/d/1Dif5M5Hw0agjgGww2k_Nn3YkAraOCQdl/view).
Filename: `CoffeyTableRecipes-2.9.0-layout-updates-test-build70.apk`.
Size: 71,775,897 bytes.

- SHA-256: `a4b5c6d4f307bca15f1cb669e6be93e58c5e46254f653bc00fef8ccde6f450fb`.
- Signing certificate SHA-256: `f8de933f14b9bb4b3191a94aedc8637972c5ab224565f6abd7808f8038d12097`.
- Package: `com.coffeytable.coffey_table_recipes`.
- Workflow passed immutable-source, version, signature, package, non-debuggable,
  timer-preferences JNI classes, and hosted Android app-link verification.
- Independent local verification passed checksum, APK signature/certificate,
  package/version, non-debuggable status, 16 KiB alignment, and
  `python3 tool/verify-app-links.py --fingerprint ACTUAL_CERTIFICATE_SHA256`.
- Uploaded to the existing recipe-app Drive folder pinned by ID; the uploaded
  APK was downloaded and its SHA-256 matched the original.

The owner explicitly authorized this destination for CTR test APKs and requested
standing destination approval, recorded in `AGENTS.md`. Automatic approval review
initially required that explicit authorization; it was obtained before uploading.

This is a test build, with no release tag, main integration, iOS/web build,
installation or release notification. Existing Drive files and permissions are
preserved. Private credentials and generated packages remain outside Git.

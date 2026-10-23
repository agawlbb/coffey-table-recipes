# Child mode visibility and AI audit — 2026-10-23

Child mode hides the wide meal planner's recipe browser, shopping-list add
input/card, recipe edit/delete controls, cooking/meal-plan/variation actions,
and Add to shopping list. Blank recipes also hide picture editing, household
attachment, meal-plan and import controls. Viewing and favorites remain available.

The AI audit covered recipe import (including photo/text/website preparation),
recipe variations, generated recipe photos, household category artwork,
administrator parent-category artwork, and recipe saves (which can suggest blank
recipe categories). The API write guard rejects these requests before network
access. The backend ChildMode guard rejects their POST routes before dispatch
to AI services. Viewing previously generated content remains available.

Two client paths were tightened: category browsing now skips automatic artwork
requests in child mode, including between category requests; an already-open
variation screen switches to the child-mode unavailable screen and its generation
handler independently checks the policy. Import and editor screens already have
child-mode unavailable screens.

Validation:

- `flutter test --no-pub test/child_mode_test.dart`: all 14 tests passed, including
  direct API rejection without network calls, dynamic import/variation screen
  locking, no automatic category generation, wide planner layout, shopping input,
  recipe actions and favorites.
- Companion suites passed in focused batched runs:
  `test/meal_planner_test.dart`, `test/shopping_list_test.dart`,
  `test/blank_recipe_detail_layout_test.dart`, `test/recipe_variation_test.dart`,
  `test/recipe_favorites_test.dart`, `test/recipe_browser_test.dart`.
  Those batches initially failed only the new shopping fixture, which lacked
  required revision/department data; the corrected child suite passed afterward.
- Dart format applied; Flutter analysis of all five changed implementation files
  and the child test reported no issues.
- `C:/xampp/php/php.exe C:/xampp/htdocs/CoffeyTableRecipes/tests/child_mode.php`
  passed. A temporary isolated child identity against the same PHP ChildMode
  class rejected all six AI/import/save POST route policies with HTTP 403
  `child_mode`. Temporary policy storage was removed; backend source unchanged.

These are source, widget, API-client and isolated server-policy checks. No real
hosted child-account login or AI provider call was performed. No app build,
hosted app publication or backend deployment was performed.

## Requested local web rebuild

The subsequent user-authorized local web rebuild used clean source
`e0ede33d11f5fb6b7be83278a0624813d50130ac`, including the child-mode changes
and the account-registration password autofill fix. Command:
`flutter build web --no-pub --base-href=/CoffeyTableRecipes/app/ --dart-define-from-file=config/firebase.local.json`.
Build and Wasm dry run succeeded. Ran `tool/prepare-web.py` and copied the
prepared assets to the ignored local XAMPP `app/` directory.

HTTP bytes for `version.json`, `main.dart.js`, `flutter_bootstrap.js` and
`assets/FontManifest.json` matched the prepared build at
http://localhost/CoffeyTableRecipes/app/. Main JavaScript SHA-256:
`65c8c0d5f8a524a08b619e972deb088225908d85bc849d3a6bbfff9e0a8ad5a7`.
Metadata identifies the source above as demonstration version 2.0.0/build 30.
No native build, release tag, hosted app publication or backend deployment.

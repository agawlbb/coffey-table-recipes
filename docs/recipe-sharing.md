# Recipe sharing

Use the standard share icon on a recipe's display page, then choose **Send a link**. The native share sheet sends a server-generated URL; browsers without sharing support show a selectable link and **Copy link**. Sharing requires a connection. Server errors appear in a snackbar and can be retried.

Anyone holding the signed link can read that recipe without an account. The PHP page displays the current recipe, in the app's cream, green and brown theme, with original measurements, photos, ingredients, method, notes, nutrition and source. Related recipe titles are displayed without granting access to other recipes. Import text and edit options are never rendered.

The backend must deploy `share.php`, `src/RecipeShare.php`, `src/RecipeSharePage.php`, the API route change and configuration default. Set a private random `recipe_share_key` of at least 32 characters in hosted `config/local.php`. No database migration is needed. Rotating the key invalidates all links; deleting a recipe or removing the sender's household membership also makes its links unavailable. Links otherwise remain valid and show subsequent recipe edits.

Validation: `flutter analyze`, `flutter test test/recipe_sharing_test.dart test/recipe_browser_test.dart test/recipe_photos_test.dart`; backend `php tests/recipe_sharing.php` and PHP lint. No hosted deployment is included in this change.

Implementation verification: 10 targeted Flutter tests and 22 backend checks passed; PHP lint passed. Full-project analysis reported two warnings in concurrently edited `offline_recipes.dart`. The built-in browser could not reach the local preview, so browser visual verification remains pending.

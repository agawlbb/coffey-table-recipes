# Recipe sharing

Use the standard share icon on a recipe display page, then choose **Send a link**. The app constructs `https://coffeybean.com/CoffeyTableRecipes/share.php?id={database recipe ID}` directly and opens native sharing. No API call or signing token is needed to create a link; if native sharing is unavailable, the selectable link and **Copy link** remain available.

The backend reads the current recipe by ID without requiring an account. Anyone can view an existing recipe by its ID. Missing recipes show a useful branded error. The cream, green and brown page includes the existing branding image, original measurements, photos, grouped ingredients, method, notes, nutrition and source. Photo surrounds match the page background. Step action chips and private import/edit data are omitted.

The revised backend was deployed and visually verified on 2026-10-11. The existing Mint Chip Ice Cream example is `https://coffeybean.com/CoffeyTableRecipes/share.php?id=9`. The hosted Flutter app was not republished.

Validation: 10 targeted sharing/browser/photo tests passed; focused analysis passed. Backend validation passed 26 checks and PHP lint; live checks verified ID lookup, missing-recipe errors, branding and protected paths.
# Food bookmark collection

Collected October 8, 2026 from the Chrome default profile's Food bookmark folder. The reviewed eight recipes were imported into Coffey (household 2) and subsequently cleaned in place.

- `bookmarks.json`: all 14 original bookmark titles and URLs.
- `recipes.json`: source Recipe JSON-LD, resolved source URLs, collection timestamps, and per-bookmark fetch status.
- `import-ready.json`: eight recipes with original ingredient wording, flattened cooking steps, structured instructions, attribution, yield, times, and source nutrition when supplied.

Run `collect.ps1` to refresh source extraction, then `prepare.ps1` to regenerate the import bundle. Collection requires network access. Neither script connects to the database.

`import.php` uses the current backend schema and configuration; it verifies household 2/user 6 and skips existing import keys. Use `--dry-run` to validate new imports with rolled-back transactions, or `--reviewed-commit` after reviewing a new recipe bundle. Original wording and units are preserved. Numeric parsing is conservative; unknown servings and nutrition remain unstructured. Cooking notes remain NULL when no genuine guidance is available. Source image references are verified through the backend's `RecipeImportTools` before insertion; no media is hosted.

For existing recipes, use the explicit cleanup/photo-backfill mode:

```powershell
C:\xampp\php\php.exe recipe-import\import.php --cleanup-existing --dry-run
C:\xampp\php\php.exe recipe-import\import.php --cleanup-existing --apply
```

This mode never deletes/reimports recipes or changes their IDs. It corrects source-supported redundant yields, removes exact bookkeeping notes and narrowly identified source taxonomy artifacts, and appends verified photos without resetting a user-selected cover. It preserves original source extraction and ingredients/instructions. Reports, verification evidence, and recovery snapshots are stored only in the backend's HTTP-blocked, Git-ignored `storage/` directory. Detailed mapping, verification, and restore instructions are in `C:\xampp\htdocs\CoffeyTableRecipes\docs\recipe-import-cleanup.md`.

The October 8 cleanup changed IDs 9–16, removed eight bookkeeping notes and four muffin category artifacts, corrected three yield strings, and inserted 18 external photo references with eight covers. Second dry-run/apply runs found no further changes. Queso's `10; 10-12 servings` remains ambiguous. CLI verification accepted all 18 images; Chrome decoded all as HTML images, while six Bon Appétit/Midwest Foodie URLs failed cross-origin decoding. Authenticated Chrome/Android recipe-flow verification remains pending; Android requires sign-in.

Eight collected recipes: Mint Chip Ice Cream; Hot Fudge Chocolate Pudding Cake; Coffee-Chocolate Layer Cake with Mocha-Mascarpone Frosting; Homemade Hamburger Buns (Bread Machine); Chinese Buffet Crab Casserole; Chinese Orange Chicken; Bran Flax Muffins; Smoked Queso.

Remaining bookmarks are recorded in `recipes.json`: five failed fetches and one page needing manual extraction. Legacy Genius Kitchen and Cafe Delites addresses were updated to their current recipe addresses. Review the collected recipes before treating them as verified cooking data.

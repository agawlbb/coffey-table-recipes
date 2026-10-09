# Hosted bookmark import

Use `export-hosted.php` to prepare data-only SQL for the existing hosted schema. It does not connect to or modify the local recipe database. Authenticate to the correct hosted database in the built-in browser and verify the household/user membership before importing the generated SQL through phpMyAdmin. Use phpMyAdmin's default stop-on-error behavior. Do not enable ignoring SQL errors. The import runs in one transaction, verifies an active owner/admin destination, skips existing source URLs/import keys, and never updates existing recipes or their children. Verify the final result rows after import; `authorized_destination` must be 1.

```powershell
& C:/xampp/php/php.exe recipe-import/export-hosted.php `
  --input=recipe-import/remaining-ready.json `
  --output=recipe-import/generated/remaining.sql `
  --household=2 --user=6 `
  --photo-archive-manifest=recipe-import/generated/photo-archive/manifest.json
& C:/xampp/php/php.exe recipe-import/test-hosted.php recipe-import/generated/remaining.sql
```

Photos must be downloaded before exporting hosted SQL. Create a JSON list of candidate URL groups (each group represents one photo, with full-size and resized URLs as alternatives), then run:

```powershell
& C:/xampp/php/php.exe recipe-import/archive-photos.php `
  recipe-import/generated/photo-candidates.json recipe-import/generated/photo-archive
```

The downloader pins validated public DNS addresses, checks every redirect, verifies TLS, limits downloads to 8 MB / 20 seconds, and validates the decoded image type and dimensions. Content-hash filenames avoid duplicate files. Review `failures.json`; recover publisher-blocked images using a browser download and validate its actual bytes before adding it to the private manifest. Never invent a replacement source photo.

Upload only `media/recipe-photos/` to `/home/hosting_account/coffeybean.com/CoffeyTableRecipes/`, including the backend's image-directory `.htaccess`. Do not upload manifests, SQL, source pages or backups into the public directory. Verify every public file's SHA-256 and CORS headers before applying SQL. The exporter requires the archive manifest and matching local bytes; `HostedImport` rejects external photo URLs or invalid storage keys. Original publisher URLs and attribution remain in the private archive/source text. Generated media and import artifacts remain outside Git.

For existing photo records, export a JSON snapshot including IDs, household, recipe, URL, storage key, MIME, dimensions, position, cover, caption and attribution. `migrate-photo-archive.php <snapshot> <manifest> <output-directory>` prepares a guarded migration and rollback scoped to household 2 / owner 6. It updates existing rows without deleting duplicates or changing recipe content/revisions. Exact old-value guards preserve concurrent photo edits. Repeat execution makes no changes. A migration to another household requires reviewing and changing the explicit destination in the planner first.

`HostedImport.php` preserves original ingredient text, parses decimal quantities and exact fractions including Unicode fractions, and leaves missing quantities and placeholder zero durations unspecified. SQL text values use UTF-8 hex literals with an explicit collation, so source apostrophes, punctuation and Unicode cannot become SQL statements. The generated files contain source material and remain outside Git.

Validation uses an isolated disposable database with the current backend migrations. It checks household authorization, exact fractions, original text, Unicode and SQL-like punctuation, cover-photo behavior, repeat imports and preservation of user edits. It never targets the application's database.

## Import status, 2026-10-09

Of the six remaining food bookmarks, five were recovered and prepared: stuffing, mojito, chicken/potato casserole, crab/mushroom wine sauce, and deep-dish pizza. Five photos validated (one stuffing, two mojito, one casserole, one pizza). Cooks supplied no recipe photo. The pizza lacks several ingredient amounts; they remain unknown. The casserole source omits milk from its ingredient list despite specifying it in the directions; that discrepancy is retained. No recipe was fabricated for the Kroger pasta-bake bookmark, whose page did not return recipe content.

The five-recipe export passed 15 checks, including execution and a repeat execution against a disposable database. After the user granted the existing `chatgpt` account access to `hosting_account_recipes`, the import completed through phpMyAdmin in the built-in browser (81 queries, partial imports disabled, foreign-key checks enabled). A separate read verified these committed rows in household 2, owned by user 6:

| ID | Recipe | Ingredients | Steps | Photos |
| --- | --- | ---: | ---: | ---: |
| 17 | Caramelized Onion and Cornbread Stuffing | 8 | 2 | 1 |
| 18 | Pitcher Cocktails: The Muddle-Free Mojito | 4 | 2 | 2 |
| 19 | Cheesy Chicken and Potato Casserole | 5 | 3 | 1 |
| 20 | Crab Meat and Mushrooms in Wine Sauce | 11 | 1 | 0 |
| 21 | Homemade Chicago-Style Deep Dish Pizza | 8 | 6 | 1 |

The local application database was not changed. Existing recipes were not updated. The Kroger bookmark remains unimported because authoritative recipe content could not be recovered; no substitute was invented. The import result screenshot and source artifacts remain in the ignored `generated/` directory.

## Hosted photo archive, 2026-10-09

Downloaded and uploaded 15 verified source-image files. Migrated all 23 external photo records to coffeybean.com; two existing hosted illustrations remain intact. All 25 photo records across 13 recipes retain their IDs, ordering, captions, attribution and cover selection. WordPress variants share one full-size archive file. Hosted checks confirm zero external image URLs, matching SHA-256 for all 15 uploads, and public-image CORS headers. The private before snapshot, rollback SQL, manifest and verification screenshot are under ignored `generated/photo-archive/`.

Validation: `test-photo-archive.php` checks private-address rejection, authorization, concurrent-edit guards, metadata preservation, idempotence and rollback in a disposable local database; `test-hosted.php` checks hosted import behavior and rejects hotlinked photos.

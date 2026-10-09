# Hosted bookmark import

Use `export-hosted.php` to prepare data-only SQL for the existing hosted schema. It does not connect to or modify the local recipe database. Authenticate to the correct hosted database in the built-in browser and verify the household/user membership before importing the generated SQL through phpMyAdmin. Use phpMyAdmin's default stop-on-error behavior. Do not enable ignoring SQL errors. The import runs in one transaction, verifies an active owner/admin destination, skips existing source URLs/import keys, and never updates existing recipes or their children. Verify the final result rows after import; `authorized_destination` must be 1.

```powershell
& C:/xampp/php/php.exe recipe-import/export-hosted.php `
  --input=recipe-import/remaining-ready.json `
  --output=recipe-import/generated/remaining.sql `
  --household=2 --user=6
& C:/xampp/php/php.exe recipe-import/test-hosted.php recipe-import/generated/remaining.sql
```

The exporter checks public source photos using the backend's existing safe image verifier. If a source image loads in the browser but rejects the server-side image request, export that observed image with the browser's page-assets capability and pass its manifest using `--browser-image-manifest=<absolute-path>`. Only assets matching the recipe's source image candidates are used. The exporter verifies the local artifact path, size, decoded image dimensions and MIME type. It retains the public source URL and attribution; image files are not uploaded to the backend.

`HostedImport.php` preserves original ingredient text, parses decimal quantities and exact fractions including Unicode fractions, and leaves missing quantities and placeholder zero durations unspecified. SQL text values use UTF-8 hex literals with an explicit collation, so source apostrophes, punctuation and Unicode cannot become SQL statements. The generated files contain source material and remain outside Git.

Validation uses an isolated disposable database with the current backend migrations. It checks household authorization, exact fractions, original text, Unicode and SQL-like punctuation, cover-photo behavior, repeat imports and preservation of user edits. It never targets the application's database.

## Preparation status, 2026-10-09

Of the six remaining food bookmarks, five were recovered and prepared: stuffing, mojito, chicken/potato casserole, crab/mushroom wine sauce, and deep-dish pizza. Five photos validated (one stuffing, two mojito, one casserole, one pizza). Cooks supplied no recipe photo. The pizza lacks several ingredient amounts; they remain unknown. The casserole source omits milk from its ingredient list despite specifying it in the directions; that discrepancy is retained. No recipe was fabricated for the Kroger pasta-bake bookmark, whose page did not return recipe content.

The five-recipe export passed 15 checks, including execution and a repeat execution against a disposable database. Hosted ingestion is pending: the currently authenticated phpMyAdmin account `hosting_account_chatgpt` exposes other databases but does not expose `hosting_account_recipes`. No hosted or local application data has been changed by this preparation. The user has authorized ingestion without a recipe approval step once the correct database session is accessible.

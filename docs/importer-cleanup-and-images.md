# Importer task: clean recipe data and add source photos

Clean the eight existing imported recipes and add their original recipe photos. Work within the current schema. Do not delete/reimport recipes, change IDs, create another household, or overwrite original quantities and instructions. Do not build AI importing, image uploading or media hosting in this task.

Flutter repository: `C:\Users\developer\StudioProjects\coffey_table_recipes`.
Server repository: `C:\xampp\htdocs\CoffeyTableRecipes`.
Database: `coffey_table_recipes`. Read server connection settings from ignored `config/local.php` through `src/bootstrap.php`; never hardcode credentials.
Installation-specific account details removed; identify your own account and household before maintenance.

Read `docs/recipe-import.md`, both repositories' `AGENTS.md`, and the migrations before starting. Commit completed source/documentation changes separately in each repository changed. Keep local extracted JSON, database backups and credentials out of Git. Do not push.

## 1. Prepare a reviewable, repeatable cleanup

Read-only inspect the current rows first. Match recipes by `(household_id, import_key)` or verified source URL; never by title alone. Preserve recipe IDs and import keys so favorites, variations and future history remain intact.

Prepare a dry-run report listing each proposed change with recipe ID/title, old value, new value, reason and source evidence. The user's request authorizes cleanup of the identified importer artifacts; uncertain culinary changes still require review. Do not guess yield, dietary suitability, timing or nutrition. Use PDO prepared statements, household-scoped predicates and transactions per recipe. Add explicit apply/dry-run modes; rerunning must produce no duplicates or repeated edits.

Before applying, save a recoverable snapshot of affected recipe/tag/photo rows and any changed steps under the backend's HTTP-blocked, Git-ignored `storage/` directory. Document the restore procedure. Preserve technical provenance in the existing `source_text` and local import records, rather than cooking notes. If source content has changed since collection, retain the original extraction and record the new evidence separately.

## 2. Correct yield and importer notes

For **Bran Flax Muffins**, current recipe ID **15**, the imported yield is `15 people`, while the last cooking instruction explicitly says `Yield: 15 medium muffins`.

- Set `yield_text` to `15 medium muffins` after verifying that same recipe/source row.
- Keep `servings` NULL: fifteen muffins does not establish how many people it serves.
- Preserve the original extracted yield in `source_text`.
- Do not remove the yield sentence from the original cooking instruction merely to avoid repetition in this task.

Inspect the other recipes for duplicated yield strings such as `4; 4 Servings` or `9; 9 serves`. Replace redundant equivalent values with one source-supported phrase. Retain ambiguous or contradictory yields for manual review; do not choose an arbitrary number or assume every numeric yield means servings.

The importer currently puts this exact bookkeeping string in `recipes.notes`:

```text
Original JSON-LD retained. Uncertain units and serving interpretation left unstructured. Source nutrition retained in source_text, not validated.
```

Remove that exact importer-generated note from affected imported recipes by setting `notes` NULL. Use an exact-match condition so genuine cooking notes are not erased. If a row combines real notes and bookkeeping, preserve real notes and review the split. Do not hide technical artifacts with a broad substring filter in Flutter.

Update `recipe-import/import.php` so future imports keep cooking notes for cooking guidance only and leave them NULL when no genuine notes exist. It should not generate new JSON, parsing or validation commentary in `notes`.

## 3. Clean category tags

Bran Flax Muffins currently has these `category` labels:

| Label | Action |
| --- | --- |
| `Bob & Charlee's Recipe Box` | Remove from recipe categories; preserve its source context in extraction/provenance |
| `Category` | Remove: generic site taxonomy heading |
| `Dietary Needs` | Remove: generic site taxonomy heading |
| `Muffins` | Keep: meaningful recipe category |
| `Soy Free` | Remove from `category`; retain only as an unverified source dietary claim in provenance |

The current tag schema supports cuisine, category, technique and equipment; it has no dietary-claim kind. Do not invent a new enum value or present a source dietary claim as verified safety advice. Do not silently discard its original provenance.

Audit the other imported tags for website headings, navigation, collection names and redundant labels. Use source context to distinguish actual recipe categories/cuisines from site taxonomy. Do not blanket-delete all unfamiliar tags or all labels containing “recipe.” Document the mapping rules and update the importer to apply them on subsequent imports. Keep source attribution out of category chips.

Increment `recipes.revision` once per recipe changed in the cleanup and set `updated_by_user_id` to the verified importing user. Existing nutrition with a different revision will correctly be flagged stale. Do not fabricate structured nutrition from the unvalidated source nutrition in this task.

## 4. Add original recipe image references

The bundle generated by `recipe-import/prepare.ps1` already retains `image_source`, but `recipe-import/import.php` currently ignores it. The database currently has no `recipe_photos` rows. Flutter supports HTTP/HTTPS images through `recipe_photos.source_url`; it does not yet serve private `storage_key` files.

Implement photo extraction from Recipe structured data. Handle:

- A single URL string.
- An array of strings or image objects.
- An ImageObject containing `contentUrl` or `url`; prefer its actual image URL over a page URL.

Resolve relative URLs against the final recipe page URL, not the old bookmark address. Accept only absolute HTTP/HTTPS image URLs with a host. Prefer HTTPS when the source actually provides it; do not rewrite arbitrary URLs and assume they exist. Reject `javascript:`, `data:`, `file:` and unrelated malformed references. Do not collect ads, logos or navigation thumbnails merely because they appear on the page.

Before inserting each image, verify it belongs to the recipe and is retrievable without a login or payment. If fetching to verify, restrict protocols to HTTP/HTTPS, reject loopback/private/link-local destinations, recheck redirected targets, use certificate validation, bounded response sizes/timeouts, and verify image content type/bytes. Do not bypass access restrictions, anti-bot pages or failed sources. Use existing public source images; do not generate substitutes or imply rights beyond the source attribution.

Insert into `recipe_photos` with:

- Verified `household_id` and existing `recipe_id`.
- Stable ordered `position` starting at 1.
- `source_url` as the original accessible image reference; `storage_key` NULL for this task.
- `is_cover=1` for one verified primary image, preferably the source's designated recipe image. Additional photos use 0. Preserve any cover already selected by the user.
- Optional source-provided `caption` and `attribution`; use the recipe publisher/source when justified. Do not invent captions or photographer credit.
- Verified `mime_type`, `width_pixels`, and `height_pixels` when available; otherwise NULL.

Deduplicate identical resolved URLs within each recipe before inserting. Check existing rows so rerunning adds nothing twice, does not reset a user-selected cover, and does not collide with existing positions. The database permits only one cover per recipe; adjust covers deliberately within the transaction if needed.

External source references may later stop working or reject hotlinking. Test the actual images in Chrome and Android: browser CORS, mixed-content restrictions and source access rules can differ from a CLI fetch. If an image fails, report the recipe/source and leave the app's fallback intact. Do not claim success solely because an HTTP request returned 200. A future media-storage task can download permitted copies and implement authorized local media delivery.

Update the importer to insert photos for new recipes. Its current “skip existing” behavior must also offer an explicit, idempotent photo-backfill/cleanup mode for the eight existing recipes; it must not silently overwrite their content or reimport them.

## 5. Verify and report

- Recipe count and IDs remain unchanged; no foreign-household rows are touched.
- Bran Flax Muffins reads `15 medium muffins`, with structured servings still unknown.
- Genuine cooking notes remain; importer JSON commentary and site headings no longer appear in the recipe view.
- Original ingredient wording, quantities, units, language and cooking instructions remain unchanged.
- Each usable image has correct recipe/household ownership, position, provenance and at most one cover.
- A second dry run/apply finds no duplicate images or further cleanup changes.
- Run backend recipe and authentication tests; add meaningful tests for ImageObject/array parsing, relative URLs, category mapping and idempotent photo backfill.
- Use Browse recipes → recipe detail in Chrome and Android to verify cover photos, detail gallery and cleaned labels. Refresh the browser collection after importing.
- Report changed recipe IDs, cleanup counts, image successes/failures, unresolved source ambiguities, test results and commit IDs. Never include credentials or full local source dumps in the report.

No schema migration should be necessary for this cleanup and URL-based photos. If a schema change becomes necessary, explain why and use a new migration; never edit an applied migration.

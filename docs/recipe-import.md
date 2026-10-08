# Recipe import handoff

Recipe storage is ready in local MariaDB database `coffey_table_recipes`. Backend root: `C:\xampp\htdocs\CoffeyTableRecipes`. This is a development-only direct database import contract, not a public API. Flutter uses authenticated recipe browsing/detail endpoints. Recipe create/update/delete API endpoints are not yet implemented.

Apply migrations with `C:\xampp\php\php.exe C:\xampp\htdocs\CoffeyTableRecipes\bin\migrate.php`. Do not modify applied migrations or create competing recipe tables. Migrations 003 and 004 establish the recipe schema. Local connection settings are in the backend's ignored `config/local.php`; do not copy credentials into source files.

## Identify the destination first

Installation-specific account details removed; identify your own account and household before maintenance.

The old Google app login and initial household were deliberately deleted. Do not recreate them, use user ID 1, or assume household ID 1. The replacement email account and household have now been created through the app. Resolve the destination using:

```sql
SELECT h.id, h.name, m.user_id, u.display_name, m.role
FROM households h
JOIN household_memberships m ON m.household_id = h.id
JOIN users u ON u.id = m.user_id
WHERE u.disabled = 0 AND m.role IN ('owner', 'admin');
```

If there are no rows, prepare reviewed structured files and wait for a household. If several destinations exist, have the user identify the household. Never invent an owner or import into another household. AI-assisted extraction should be reviewed by the user before saving, as required by the project specification.

## Tables

| Table | Purpose |
| --- | --- |
| `recipes` | Household, original-language title/content, provenance, yield, optional times, variation parent, revision and authors |
| `recipe_ingredient_groups` | Ordered headings, such as sauce and filling |
| `recipe_ingredients` | Ordered individual ingredients with preserved wording, original quantities/units, preparation and flags |
| `recipe_steps` | Ordered instructions and optional section heading |
| `recipe_step_actions` | Timers, temperatures, resting periods and reminders |
| `recipe_photos` | File references or source URLs, captions, attribution, ordering, single cover |
| `recipe_tags` | Cuisine, category, technique and equipment labels |
| `recipe_pairings` | Explicit unordered recipe pairs within the household |
| `recipe_favorites` | Recipe favorites for household people, including people without logins |
| `recipe_nutrition` | Estimated nutrition with basis, method, source and recipe revision |
| `cooking_events` / `cooking_event_recipes` | One meal/cooking event with multiple recipes and per-recipe notes |

All child rows require the same `household_id` and their parent IDs. Composite foreign keys reject cross-household links and ingredient groups/steps belonging to another recipe. These constraints supplement authorization; any future API must still verify membership and write permissions.

## Import rules

Use prepared statements and a transaction per complete recipe or related recipe batch. Use the actual inserted IDs returned by `lastInsertId()`. Positions start at 1 and are unique within their recipe (actions within their step). Unknown optional values are SQL NULL, not zero or fabricated estimates. Minimal recipes need a household and nonempty title; ingredients and steps are separate rows, never merely `source_text`.

Set `original_language` to the source's language tag, such as `en` or `fr`. Store original title, ingredient wording and instructions in that language. Preserve original extracted text in `source_text` when useful and provenance in `source_type`, `source_url`, `source_title`, `source_author`, and `source_reference`. Do not replace original fields with translations; translated representations will get a separate later migration. `measurement_system` (`metric`, `us`, `mixed`, `unspecified`) is independent of language.

Set a stable ASCII `import_key` (at most 191 characters), such as a SHA-256 of the source identity, to prevent duplicate imports within a household. Multiple NULL keys are allowed. Before retrying a batch, look up that key and skip or ask before updating. Do not deduplicate solely by title and do not silently overwrite recipes. Set `created_by_user_id` and `updated_by_user_id` to the active importing household user where known; they may be NULL for a documented development import.

### Quantities and units

- `original_text` preserves the whole ingredient line. `ingredient_name` is the searchable ingredient name in the original language.
- `quantity_text` preserves wording such as `1 1/3`, `2–3`, `a pinch`, or `to taste`.
- Decimal quantities use `quantity_decimal` as a decimal string, never a binary floating-point conversion. Example: `250.0`.
- Exact fractions use `quantity_numerator` and `quantity_denominator` instead of `quantity_decimal`. Example: `1 1/3` = numerator 4, denominator 3. Do not populate both representations.
- Decimal ranges use `quantity_decimal` for the lower bound and `quantity_max_decimal` for the upper bound. Fraction ranges or ambiguous quantities can retain their original `quantity_text` with structured amounts NULL.
- Preserve `original_unit` exactly. Optional `unit_code` identifies an unambiguous unit (`g`, `kg`, `ml`, `l`, `us_cup`, `us_tbsp`, `us_tsp`, `oz_mass`, `lb_mass`). Leave it NULL if the source unit is ambiguous. Do not infer grams from cups without ingredient-specific density, or convert original values destructively.
- Set `scale_quantity=0` for amounts that should not scale automatically; use `is_main_ingredient=1` for principal ingredients and `is_optional=1` where appropriate.

### Steps, actions and photos

Human-readable instructions remain authoritative. Action types: `timer`, `appliance_temperature`, `internal_temperature`, `rest`, `reminder`. Timers/rest require positive `duration_seconds`. Temperatures require both exact `temperature_value` and original `temperature_unit` (`C` or `F`); preserve 180°C as 180°C. Actions are data only and do not control appliances.

Photos store no image binaries. Use `storage_key` for a relative media key such as `households/<id>/recipes/<id>/<opaque-name>.jpg`, or `source_url` for a preserved original image reference. URLs are not automatically downloaded or guaranteed to remain available. Media upload/serving is not implemented yet. Record attribution, MIME type and dimensions when known. At most one photo per recipe can have `is_cover=1`. Unknown photos may simply be omitted.

### Relationships, history and nutrition

A variation is a complete recipe with its own children and a same-household `parent_recipe_id`. Insert the parent first. Do not create self-links or cycles; the importer/service must enforce an acyclic parent tree (foreign keys do not enforce that). Canonical promotion will be a later service operation.

Explicit pairings store the smaller recipe ID in `recipe_id` and the larger in `paired_recipe_id`. One row represents both directions. Inferred pairings should later be computed from shared cooking events, not inserted as explicit pairings.

Favorites use actual `household_people.id`, not user IDs. Cooking events use UTC `cooked_at` and may contain multiple recipe rows; preserve event notes and per-recipe notes. Do not fabricate cooking history.

Nutrition fields are optional: `calories_kcal`, `protein_g`, `carbohydrate_g`, `fat_g`, `saturated_fat_g`, `fiber_g`, `sugar_g`, `sodium_mg`. Default basis is `per_serving`; use `whole_recipe` if appropriate. Include `method`, source reference and `recipe_revision`. Increment `recipes.revision` on edits, especially ingredients/quantities/yield. Nutrition is stale whenever its recorded revision differs from the recipe revision. Do not invent nutrition or imply estimated values are laboratory measurements.

Recipe deletion cascades content, photos, favorites, nutrition and pairings. Deleting an ingredient group also deletes its ingredients; move ingredients to another group or set their `group_id` NULL first if preserving them. Variations and cooking history intentionally prevent recipe deletion until handled deliberately.

## Minimal transaction example

Replace the household/user variables with verified destination IDs. This is illustrative SQL; production/import code should bind values using PDO prepared statements.

```sql
START TRANSACTION;
INSERT INTO recipes (household_id, title, original_language, measurement_system,
    source_type, import_key, servings, created_by_user_id, updated_by_user_id)
VALUES (@household_id, 'Example metric recipe', 'en', 'metric',
    'reviewed_text', 'example-source-identity', 4, @user_id, @user_id);
SET @recipe_id = LAST_INSERT_ID();
INSERT INTO recipe_ingredients (household_id, recipe_id, position,
    original_text, ingredient_name, quantity_text, quantity_decimal, original_unit, unit_code)
VALUES (@household_id, @recipe_id, 1, '250 g flour', 'flour', '250', '250', 'g', 'g');
INSERT INTO recipe_steps (household_id, recipe_id, position, instruction)
VALUES (@household_id, @recipe_id, 1, 'Mix the ingredients.');
COMMIT;
```

Do not run the example as seed data. Recipes appear in the app through Browse recipes after import. Use the refresh button to retrieve newly imported rows.

Verify schema behavior with `C:\xampp\php\php.exe C:\xampp\htdocs\CoffeyTableRecipes\tests\recipe_schema.php`. The test uses a disposable database and leaves real recipe data unchanged.

# Browsing recipes by category

The recipe home lists Main dishes, Side dishes, Desserts, Drinks, Breakfast and
Appetizers in illustrated cards styled like recipe cards. Select a main category
to see its populated subcategories, then a subcategory to see its recipes.
Recipe counts avoid counting the same recipe twice within a main category.

Search from home searches all recipes available to the current household. At
other levels it searches only the selected main category or subcategory. Search
results open recipe details directly. Clear search to return to the current
category list. The bottom Back button moves up one category level and clears
search; at home it clears search. Recipe details also have a bottom back button.

The hosted schema and all 13 existing hosted recipes were updated on 2026-10-09.
The local database remains independent and unchanged. Category assignments and
the catalog are documented in the PHP repository's `docs/recipe-categories.md`.
Artwork is bundled in `assets/categories/` for both web and Android.

Verification: all 12 Flutter tests pass, Flutter analysis reports no issues, and
web plus Android debug builds succeed using the hosted API default. Widget tests
exercise all three levels, global/main/subcategory search, clearing search,
bottom back navigation and opening/returning from structured recipe details.

Live verification with a signed-in household confirmed the six category counts,
the Main dishes subcategory list, scope excluding muffins from Main dishes,
Chinese search returning only Orange Chicken, preserved recipe ingredients,
and the bottom buttons returning from details and the recipe list.
Home search for muffins finds both Bran Flax Muffins and the stuffing recipe
that contains cornmeal muffins. The three-level navigation test also passes at
a 320px phone width without layout errors.

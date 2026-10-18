# Browsing recipes by category

Recipe detail steps show the step number before the heading, followed by the
instructions. Cooking mode includes the heading alongside its numbered step.
Steps without headings retain their normal numbered instructions.

The recipe home lists Main dishes, Side dishes, Desserts, Drinks, Breakfast and
Appetizers in illustrated cards styled like recipe cards. Select a main category
to see its populated subcategories, then a subcategory to see its recipes.
Recipe counts avoid counting the same recipe twice within a main category.

Recipe tiles show only the recipe name and picture; descriptions, yield and time
information remain in recipe details. The web header omits the account name next
to the user menu. Mobile offline downloads show no recipe counts or completed
download notice; preparation and actionable failure/retry status remain available.
Validation: 28 browsing/offline regression tests pass and Flutter analysis is clean.

Search from home searches all recipes available to the current household. At
other levels it searches only the selected main category or subcategory. Search
results open recipe details directly. Clear search to return to the current
category list. The tappable trail beneath search always shows All Recipes and
each selected category. Tap any label to return directly to that level and clear
search. The bottom back arrow moves up one category level and clears search;
at home it clears search. Recipe details also have a bottom back arrow.

The hosted schema and all 13 existing hosted recipes were updated on 2026-10-09.
The local database remains independent and unchanged. Category assignments and
the catalog are documented in the PHP repository's `docs/recipe-categories.md`.
Artwork is bundled in `assets/categories/` for both web and Android.

Verification: all 12 Flutter tests pass, Flutter analysis reports no issues, and
web plus Android debug builds succeed using the hosted API default. Widget tests
exercise all three levels, global/main/subcategory search, clearing search,
bottom back navigation, jumping to each breadcrumb level, and opening/returning
from structured recipe details.

Live verification with a signed-in household confirmed the six category counts,
the Main dishes subcategory list, scope excluding muffins from Main dishes,
Chinese search returning only Orange Chicken, preserved recipe ingredients,
and the bottom buttons returning from details and the recipe list.
Home search for muffins finds both Bran Flax Muffins and the stuffing recipe
that contains cornmeal muffins. The three-level navigation test also passes at
a 320px phone width without layout errors.

2026-10-15: Category navigation reads saved mobile browse text before making a network request, and reuses visited browse responses during the current session on all platforms. Refresh, search, recipe changes and reconnect reload from the server and clear session responses. Missing cached scopes still load normally. Category artwork is fetched after text is displayed and cannot hold navigation open; late image results are ignored after changing scope. Validation: 38 browser/offline cache tests pass, including delayed-network and delayed-artwork regressions.

2026-10-16: Search updates while typing and uses saved recipe text first, including ingredient matches from the mobile synced library. A nonempty query shows recipes only and requests tree=0. Clearing search restores cached categories. Search remains scoped to the selected category. Uncached network searches debounce for 250 ms; stale results cannot replace the latest query. Explicit Refresh continues to fetch current data.

2026-10-17: Tapping a duration chip on the recipe view explains that timers are used in cooking mode. The dialog offers Cancel and Open cooking mode; opening cooking mode does not automatically start a timer. Temperature chips remain informational. The timer-navigation regression covers both dialog actions and checks that no native timer is scheduled by navigation.

2026-10-18: Household navigation is available from recipe details (including related recipes) and cooking mode, alongside the Back control. Selecting Recipes from the menu closes deeper routes and recreates top-level browsing with search, category scope, favorites and blank-only filters cleared. Other menu destinations also return to the household root before opening. Navigation regressions cover returning from browsing, recipe details and cooking mode, with active filters; existing phone/desktop home tests reflect the reset behavior. No app build was created.

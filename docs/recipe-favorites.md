# Recipe favorites

Tap the heart beside edit/share/delete to toggle your own favorite. Hold the heart to select household people, including members without accounts, then save. A Favorite of line appears after steps and before notes when anyone has favorited the recipe.

Use Filters beside search, then Favorite, to select household members. Every checked person must favorite the recipe for it to appear. Apply refreshes the current search/category; Clear and Apply remove the restriction. Matching variations are listed individually. Favorites remain private to the selected household.

Favorites changes and filtered browsing require a connection. Offline browsing never substitutes unfiltered results for an active favorite filter.

Validation: favorites widget tests cover self toggling, long-press household editing, displayed names, multi-person filters and clearing. API tests verify authenticated filtered reads. Relevant browser, API and offline suites pass (61 tests total).

The backend is maintained and committed separately, with migration 013 and a backed-up hosted deployment. No app package or frontend deployment is part of this feature change.

Hosted validation on 2026-10-17: backend fab223c3227bc004e6677b872401f62174d0418b deployed successfully in https://github.com/agawlbb/coffey-table-recipes-server/actions/runs/39051219333. All 91 Python workflow checks and PHP validation passed. Migration 013 saved a protected backup, retained all 38 recipes and restored database privileges. Public receipt matches the commit; health is OK; unauthenticated favorites reads and filtered browsing return 401. Authenticated production writes have not been exercised; local authenticated-service fixtures cover those behaviors. Flutter analysis is clean. App source commit: 0411299.

# Recipe favorites

Tap the heart beside edit/share/delete to toggle your own favorite. Hold the heart to select household people, including members without accounts, then save. A Favorite of line appears after steps and before notes when anyone has favorited the recipe.

Use Filters beside search to select Favorite of members. Every checked person must favorite the recipe for it to appear. Apply refreshes the current search/category; Clear and Apply remove the restriction. Matching variations are listed individually. Favorites remain private to the selected household.

Favorites changes and filtered browsing require a connection. Offline browsing never substitutes unfiltered results for an active favorite filter.

Validation: favorites widget tests cover self toggling, long-press household editing, displayed names, multi-person filters and clearing. API tests verify authenticated filtered reads. Relevant browser, API and offline suites pass (61 tests total).

The backend is maintained and committed separately, with migration 013 and a backed-up hosted deployment. No app package or frontend deployment is part of this feature change.

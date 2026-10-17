# Recipe favorites

Tap the heart beside edit/share/delete to toggle your own favorite. Hold the heart to select household people, including members without accounts, then save. A Favorite of line appears after steps and before notes when anyone has favorited the recipe.

Use Filters beside search to select Blank recipes only or expand Favorite in the same panel to select household members. Selected names appear under Favorite, and existing selections reopen expanded. Every checked person must favorite the recipe for it to appear. Apply refreshes the current search/category; Clear and Apply remove the restriction. Matching variations are listed individually. Favorites remain private to the selected household.

Favorites changes and filtered browsing require a connection. Offline browsing never substitutes unfiltered results for an active favorite filter.

Validation: favorites widget tests cover self toggling, long-press household editing, displayed names, multi-person filters and clearing. API tests verify authenticated filtered reads. Relevant browser, API and offline suites pass (61 tests total).

The backend is maintained and committed separately, with migration 013 and a backed-up hosted deployment. No app package or frontend deployment is part of this feature change.

Hosted validation on 2026-10-17: backend fab223c3227bc004e6677b872401f62174d0418b deployed successfully in https://github.com/agawlbb/coffey-table-recipes-server/actions/runs/39051219333. All 91 Python workflow checks and PHP validation passed. Migration 013 saved a protected backup, retained all 38 recipes and restored database privileges. Public receipt matches the commit; health is OK; unauthenticated favorites reads and filtered browsing return 401. Authenticated production writes have not been exercised; local authenticated-service fixtures cover those behaviors. Flutter analysis is clean. App source commit: 0411299.

Filter review (2026-10-17): the dialog uses aligned labels and trailing checkboxes, matching household favorite selection. Decorative icons beside Blank recipes only and Favorite are omitted to avoid resembling extra controls. Clear is in the header; Cancel and Apply remain together in the footer. There is no explanatory helper copy. Clear stages a reset until Apply, while Cancel/Escape discard draft changes. Long lists scroll with a visible scrollbar and the action buttons remain outside the scroll area. Selected names remain under Favorite.

The dialog opens immediately while members load. A failed member read offers Retry within Favorite and leaves Blank recipes only usable. Applying unchanged choices avoids a browse reload. Active filter chips below search open the dialog when tapped and remove their own restriction through their delete control, retaining the other filters, search and category scope.

Validation: filter dialog/widget tests cover phone and desktop alignment, large text, long lists, keyboard dismissal, pending/failed member reads, retry, draft isolation, unchanged Apply, and independent filter-chip removal. Optional `RECIPE_FILTER_PREVIEW_DIR` and `FLUTTER_ROOT` produce PNG previews during widget tests. No app build or deployment was performed for this review.

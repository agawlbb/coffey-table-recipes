# Foundation verification

Verified October 8, 2026:

- Flutter static analysis: no issues.
- Two API client unit tests: passed.
- Flutter web production build: succeeded.
- Android debug build and installation on CoffeyTable Pixel 8 API 36: succeeded.
- Android integration test: meal-plan home rendered and connected to the actual XAMPP API; no Flutter rendering exception.
- In-app browser preview: visually inspected; displayed Recipe service connected.
- PHP syntax checks and Composer manifest validation: passed.
- Household migration applied to coffey_table_recipes; second invocation applied nothing.
- Configuration, migration files, storage, and Composer metadata: HTTP 403.
- Health endpoint: HTTP 200; unsupported method: 405; unimplemented household endpoint: 404.
- CORS: localhost:8080 allowed; unrelated origin received no allow-origin header.

XAMPP's global wildcard CORS headers caused duplicate allow-origin values initially. Project-local Apache overrides remove those inherited headers without modifying other applications.

At the foundation checkpoint, Firebase authentication and household authorization endpoints were not yet implemented. The authentication checkpoint below records their subsequent verification. Recipes, notifications, cPanel deployment, and iOS compilation remain subsequent checkpoints.

Run the emulator integration test with Apache running:

```powershell
flutter test integration_test/foundation_test.dart -d emulator-5554
```

## Authentication checkpoint — October 8, 2026

- Firebase project coffey-table-recipes created on Spark; Google provider enabled; Android/web registered.
- Local configuration files ignored; no service-account private key required for token verification.
- Flutter analysis clean; four API client unit tests passed.
- PHP suite: 30 authentication and household checks passed in a separate disposable database.
- PHP syntax checks and Composer validation passed; Composer audit reported no known dependency advisories.
- Google public signing certificates retrieved over HTTPS with certificate validation enabled.
- Unauthenticated/malformed token requests to the live identity endpoint returned 401.
- Android Firebase-configured integration test passed: actual Firebase initialization, Google sign-in button, real API connection, and no rendering exception.
- Live Google web sign-in completed with user assistance at the Google account chooser, whose automation input timed out.
- Authenticated household creation succeeded through the web UI; owner membership and linked person verified in MySQL.
- Chrome reload preserved authentication and retrieved the household again.

Native Android Google account selection has not been exercised end-to-end. Firebase plugins currently emit a future Kotlin plugin compatibility warning, but builds and the integration test succeed with the installed Flutter SDK. iOS configuration and compilation are still pending.

## Email account checkpoint — October 8, 2026

- Firebase Email/Password enabled. App supports registration, sign-in, and password reset.
- Flutter analysis clean; four unit tests and Android emulator integration test passed. Integration check covers email controls, scrolling to the live API status, and absence of rendering exceptions.
- PHP suite: 32 checks passed, including signed password-provider tokens and prevention of disabled profile restoration. Modified PHP files pass syntax checks.
- Web build published to local XAMPP; required-field validation and registration fields verified in Chrome.
- At the user's confirmed request, the initial Firebase app user was deleted and the empty household, membership, and person records removed. A disabled local UID with no display name remains solely to reject previously issued tokens.
- Creating the replacement account and testing a real email/password login require the user to enter and submit their own password. Password reset delivery has not yet been exercised.

## Recipe storage checkpoint — October 8, 2026

- Migrations 003 and 004 applied to the prototype database. Repeat migration run applied nothing.
- Structured household-owned recipe storage includes ingredients/groups, exact decimals/fractions, steps/actions, photos, tags, variations, pairings, favorites, nutrition and grouped cooking history.
- 29 recipe schema checks passed in a disposable database, including cross-household rejection, wrong-recipe group/step rejection, duplicate cover/import protection, original quantities/temperature, stale nutrition detection and content deletion cascades.
- Existing 32 authentication and household checks still pass.
- [Recipe import contract](recipe-import.md) documents the development import destination and fields. The user created the replacement email account and Coffey household (household 2, owner user 6). No recipes were seeded, and no recipe UI or CRUD API is included in this checkpoint.

## Chrome mouse cursor

The app supplies an explicit basic cursor fallback. The Add a person field uses the arrow cursor on web because the user reported the native text pointer disappearing there. Text editing retains its normal caret; native platforms retain their text mouse cursor. Flutter analysis passes.

## Recipe browsing and detail checkpoint — October 8, 2026

- Read-only GET `/households/{id}/recipes?q=...&offset=...` provides literal title/description/ingredient/tag search and 30-row pages, with `next_offset` when another page exists.
- GET `/households/{id}/recipes/{recipeId}` returns original content, ingredient groups, ordered steps/actions, photo metadata, tags, source, nutrition/staleness, recipe family and explicit pairings. Both routes verify identity, account status and household membership. Wrong-household recipe requests return 404.
- Flutter Browse recipes opens from the selected household. Search, refresh, pagination, loading, retry and empty states are implemented. Detail is a scrolling cooking-readable layout with original wording and units.
- No editing, measurement conversions, running timers or meal-plan changes included. External photo URLs display with fallback icons. Protected local media delivery is still pending; current eight imported recipes have no photo rows.
- Flutter analysis passes; six unit/widget tests pass; Android emulator fixture-based navigation/detail checks pass. PHP: 37 recipe/isolation checks and 32 authentication checks pass.
- Chrome live Firebase session retrieved actual Coffey recipe data through the API; Chinese Orange Chicken ingredients and ordered method inspected. Android recipe rendering tests use deterministic fixtures, not a real email login.

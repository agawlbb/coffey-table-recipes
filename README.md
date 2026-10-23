# Coffey Table Recipes

Flutter client for Android, iOS, and responsive web. The PHP API lives in `C:\xampp\htdocs\CoffeyTableRecipes`.

## Run locally

The app defaults to https://coffeybean.com/CoffeyTableRecipes/api/v1 on every platform. The local PHP source remains available for development; the persistent database is hosted exclusively.

```powershell
flutter run -d emulator-5554 --dart-define-from-file=config/firebase.local.json
flutter run -d chrome --web-port=8080 --dart-define=API_BASE_URL=http://localhost/CoffeyTableRecipes/api/v1
```

The first command uses the hosted backend. The second is only for an independently configured backend; the retired local recipe database is not available.

Override the address with `--dart-define=API_BASE_URL=https://your-host.example/api/v1`. Physical Android devices require the computer's reachable LAN address. Android debug builds allow local HTTP; deployed builds should use HTTPS.

```powershell
flutter analyze
flutter test
flutter build web
```

During development, web builds use a custom bootstrap without an offline service worker and fetch fresh bootstrap/entry-point URLs. The web-only Reload app button reloads with a fresh URL; previous Flutter service workers for this app are unregistered on startup. Deploy `build/web/.htaccess` along with the other files to Apache hosting with `mod_headers` and header overrides enabled: it requests no browser caching for this development deployment. Other hosts need equivalent `Cache-Control: no-store` response headers. These changes take effect after deploying the new build; an already-open older build may need Ctrl+Shift+R once. Restore production caching and remove the development button when ready for release.

Recipe details use the standard top-left app-bar back button. Category/search back navigation sits at the start of the breadcrumb row above the results. Email sign-in groups username and password autofill hints and asks the platform to save credentials only after successful authentication; password-manager behavior still depends on the browser and extension.

The signed-in home displays recipes from the hosted API, with search, category browsing, and cooking mode. Account and household management are available through the app bar and navigation menu. A small version/build label at the bottom of the navigation menu identifies the running app from its package metadata. No simulated sign-in or development authorization bypass is provided.

Each browsing scope shows sage-green category cards followed by a horizontal divider and cream-colored recipe cards. The recipe list includes recipes in descendant categories; use Load more recipes to continue through the scope. Search stays within the selected scope.

See [authentication](docs/authentication.md) for configured sign-in commands, [browsing](docs/recipe-browsing.md) for navigation, [timers](docs/timers.md) for alarm controls, and [release records](docs/releases.md) for verified platform delivery. Run/build commands require the explicit build or release authorization described in [AGENTS.md](AGENTS.md).

## Platforms

Android and web can be built here. iOS source is included; building and signing iOS requires macOS/Xcode and Apple configuration.

## Cached recipes and offline use

Android and iOS download the full recipe text collection after a successful signed-in household load, including recipes that have never been opened. Text downloads run before category metadata and include ingredients, instructions, nutrition and related recipes. A small status above the recipe browser shows download progress and reports “All N recipes saved offline” only after every recipe has been saved to disk. Keep the app connected until that message appears before testing offline access. Each launch or return to the app checks the recipe inventory and downloads newly added or missing text immediately. Already saved details refresh at most once per 24 hours unless their list metadata changed; normal online browsing still requests current data. No server changes or database export are required.

A returning, already signed-in user can restart offline, browse categories, search saved titles, descriptions, ingredients, tags and category labels, and use recipe details and cooking mode. Text is stored in application support files, separately for each Firebase account and API server. Every batch of up to three downloaded recipes is saved with a resumable manifest, including successful peers of a failed request. Closing and reopening resumes missing downloads rather than starting over. An interrupted update keeps the previous complete collection; a first partial download can browse the text already saved. Category or people failures cannot prevent text caching; if category metadata is unavailable, offline browsing shows the saved recipes as a flat list. Incomplete downloads retry every 30 seconds while online in the foreground, and the status provides a Retry action. Storage failures are reported and cannot mark the collection complete. New sign-in and account/household changes require a connection. Confirmed access denials and removed memberships invalidate saved access.

Recipe photos viewed on mobile use a disk cache targeting the 100 most recently used images, with images unused for 90 days eligible for cleanup. Photos are downloaded on demand, rather than downloading the entire photo library. The operating system may reclaim image cache files; missing images show the existing recipe placeholder. The cache manager's cleanup is asynchronous, so the object count is a target rather than a strict byte limit. See the [cache manager configuration](https://pub.dev/documentation/flutter_cache_manager/latest/flutter_cache_manager/Config-class.html).

A small cloud-off icon and “Offline” label appear at the bottom right, including in recipe details and cooking mode. The app checks network changes, resume events and (while offline in the foreground) a 30-second retry to recover when internet access returns. Temporary server failures (HTTP 408, 500, 502, 503 and 504) can use saved mobile recipe text, just like a lost connection. Authorization and deletion errors still surface and invalidate saved access as appropriate.

Across platforms, API reads retry temporary communication failures twice, after 0.5 and 1.5 seconds. AI import preparation retries once after 2 seconds, keeping the source and clarification answers and displaying a retry notice. Persistent failures leave the input available for a manual retry. A temporary failure while refreshing an open recipe keeps its loaded content visible. Saves, deletes and other mutations are not automatically replayed because a lost response may conceal a successful write. Shopping lists retain their separate revision-aware recovery. Background connection probes do not treat a temporary server failure as a successful reconnection.

Recipe browsing shows available cached text before refreshing, including after returning from the shopping list, reconnecting, or resuming the app. Missing category metadata does not hide downloaded recipes: incomplete snapshots are displayed and refreshed in the background. Category cards become usable before supplemental recipe requests finish. Refreshing the same scope keeps its current content visible; confirmed access denials still remove it. Browse requests have a 30-second UI deadline (including authentication and persistence), and a stalled local cache read falls back to the network after 2 seconds. With no cached data, a failed request offers Retry instead of an endless loading indicator. Regression coverage is in `test/recipe_browser_test.dart`, `test/recipe_search_test.dart`, and `test/offline_recipes_test.dart`.

Individual recipe pages, including related variations and blanks, also display their saved snapshot before refreshing. A failed refresh keeps existing content visible except for confirmed authorization/deletion responses (401/403/404). Startup can restore household browsing context from the account-scoped cache while account verification continues; cached roles never grant administrator actions. Previously saved favorite-filter results are reused only for the exact selected people, without inventing unfiltered results. If individual recipes exist without a library index, root browsing lists those saved recipes while refreshing the index.

The web app saves viewed browse and recipe responses in account/server-scoped local storage without downloading the full mobile library. Public shared-recipe links use a separate public-only cache. Browser storage can be cleared or unavailable, and loading the web application itself still requires its app assets. Persistent caching begins when this source is built and deployed; it cannot recover data that older web versions never saved. Validation in `test/recipe_communication_test.dart` covers cached startup during an indefinitely stalled account refresh, first-open detail display, server/firewall/rate-limit failures, bounded detail loading, and access-denial removal.

Validation: `flutter test test/offline_recipes_test.dart` includes real native file replacement and restart persistence, all-page/detail sync, category and ingredient search, account isolation, partial first-download restart/resume, metadata failures, per-recipe failures, access errors, membership removal, storage failure, completion status and offline detail rendering without photos. For a device smoke test, sign in against the hosted API, wait for “All N recipes saved offline,” enable airplane mode, force-close/reopen, search an unvisited recipe, open cooking mode and revisit a viewed photo. Disable airplane mode and verify the badge disappears. Android builds can be checked here; iOS builds and airplane-mode checks require macOS/Xcode and a device.

## XAMPP web address

Run tool/publish-local-web.ps1 to build and copy the web app into the XAMPP app directory. Then open http://localhost/CoffeyTableRecipes/. This build works while Apache is running, without the Flutter development server. Republish after source changes.


For a phone connected through a hotspot or local Wi-Fi, open http://<laptop-IP>/CoffeyTableRecipes/app/. The page is served by the laptop, while authenticated requests use the hosted API. Republish after app source changes.

## Home screen design

Main categories retain their established display order (Main dishes, Side dishes, etc.). Within a category, subcategories display alphabetically, and recipe lists use alphabetical title order, ignoring letter case. This applies to online and cached offline browsing and to loaded recipe pages.

The signed-in home opens directly to recipe search and the collection. The app bar avatar opens a standard user menu with account identity, Change name at the table, Change account display name, Household & people, and Log out. Account display names save to Firebase. Your name at the table updates your existing household member record, independently for each household; the same editor is available beside your own name in People at your table. Log out requires confirmation. The navigation menu opens Household & people for household selection, setup, and member management; returning to Recipes preserves the search. Signed-out users land directly on the sign-in form, including after logout. Artwork remains bundled for future branding use but is not shown on the home screen. The app retains its parchment, olive, coffee, and copper palette.

On mouse-only web devices, scrollable lists and photo strips use persistent, slim 7-pixel scrollbars with a muted olive thumb and no visible track. Drag the thumb or click its track area to navigate. Browsers reporting touch capability (including hybrid laptops) hide the bars and retain swipe scrolling. Native mobile scrolling is unchanged.

Recipe detail photos fit completely inside a frame no taller than 240 pixels or 30% of the viewport height. Distinct photos have previous/next buttons; WordPress size variants of the same photo display only once, with the selected cover retained. Orange Chicken's original and three resized variants therefore appear as one photo. Stored source references are preserved.

Imported recipe photos are downloaded and served from coffeybean.com under `CoffeyTableRecipes/media/recipe-photos/`. Photo records use the hosted URL and storage key; publisher URLs remain in the private import archive for provenance. See `recipe-import/HOSTED_IMPORT.md` for the archive and upload workflow.

Recipe review catches decimal/fraction conflicts before save, expands the affected ingredient and Exact quantities section, highlights the conflicting fields, and scrolls them into view. AI prefills use one valid quantity representation; backend errors identify the ingredient or action.

AI image generation is offered only when no draft or saved recipe photos exist, with no daily
attempt cap. Saving a new category generates specific category artwork; browsing
retries missing artwork for previously imported categories. Category images use
the backend media URL rather than the parent category asset.

Imported category review shows Parent category before Category name. Imports generate missing recipe descriptions and classify filled pie shells as Pies under Desserts, including recipes without a title.

Import offers Pasted recipe text and Describe how I make a dish separately. Source labels use plain language and remain identifiable after clarification. Cooking notes collect useful source tips; estimation commentary is omitted and import validation warnings appear separately during review.

Android and iOS can receive shared PDFs, images, text files, recipe text and HTTPS
links. iOS sharing uses a paid developer team's App Group: the receiver stages
the share, then you open the main app to review it with your existing sign-in.
Both iOS targets require Apple-native signing with matching App Group membership.
Android shares wait for sign-in and a household in the app before analysis.
Multiple files are reviewed one at a time. Failed
imports retain their input during the session; no recipe is saved automatically.
See [mobile sharing setup](docs/mobile-share-import.md) for signing, limitations
and device validation. `tool/build-ios-signed.sh` archives and exports on a Mac
after the paid account is configured in Xcode.

Recipe review suggests food pictures from uploaded images and supported embedded PDF images. Pictures are cropped locally and saved only after choosing Use this picture and Save. Skip picture declines a suggestion. Categories offer Type a new category and Add a new category; select the parent first, then type the name. Matching categories are reused and new names are created on Save.

## Open-source use

This project is licensed under GNU AGPL-3.0-only. See LICENSE and NOTICE.md for
source, network-service, artwork, and dependency notices. Source repositories:
[Flutter app](https://github.com/agawlbb/coffey-table-recipes) and
[PHP backend](https://github.com/agawlbb/coffey-table-recipes-server).

Use your own Firebase project, database, hosting, email and optional AI credentials
for independent installations. Local configuration, signing material, uploaded
media, personal imports and generated packages must stay outside version control.
The default coffeybean.com endpoint is the project deployment, not a free backend
for unrelated installations. AI access and existing public recipe sharing remain
unchanged by publication.

History was sanitized before publication. Existing contributors must make a fresh
clone rather than merging old history back. Earlier validation commit hashes and
Actions links in release notes refer to private, retired pre-publication records;
version labels and factual validation results are retained.

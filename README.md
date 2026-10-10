# Coffey Table Recipes

Flutter client for Android, iOS, and responsive web. The PHP API lives in `C:\xampp\htdocs\CoffeyTableRecipes`.

## Run locally

The app defaults to https://coffeybean.com/CoffeyTableRecipes/api/v1 on every platform. The local PHP project and database remain available in XAMPP.

```powershell
flutter run -d emulator-5554
flutter run -d chrome --web-port=8080 --dart-define=API_BASE_URL=http://localhost/CoffeyTableRecipes/api/v1
```

The first command uses the hosted backend. The second explicitly selects local Apache on port 80; start Apache and MySQL before using that override.

Override the address with `--dart-define=API_BASE_URL=https://your-host.example/api/v1`. Physical Android devices require the computer's reachable LAN address. Android debug builds allow local HTTP; deployed builds should use HTTPS.

```powershell
flutter analyze
flutter test
flutter build web
```

During development, web builds use a custom bootstrap without an offline service worker and fetch fresh bootstrap/entry-point URLs. The web-only Reload app button reloads with a fresh URL; previous Flutter service workers for this app are unregistered on startup. Deploy `build/web/.htaccess` along with the other files to Apache hosting with `mod_headers` and header overrides enabled: it requests no browser caching for this development deployment. Other hosts need equivalent `Cache-Control: no-store` response headers. These changes take effect after deploying the new build; an already-open older build may need Ctrl+Shift+R once. Restore production caching and remove the development button when ready for release.

Recipe details use the standard top-left app-bar back button. Category/search back navigation sits at the start of the breadcrumb row above the results. Email sign-in groups username and password autofill hints and asks the platform to save credentials only after successful authentication; password-manager behavior still depends on the browser and extension.

The signed-in home displays recipes from the hosted API, with search, category browsing, and cooking mode. Account and household management are available through the app bar and navigation menu. No simulated sign-in or development authorization bypass is provided.

See `docs/checkpoints.md` for the agreed implementation sequence and `docs/authentication.md` for configured sign-in commands. Default Flutter icons remain until the selected artwork is supplied.

## Platforms

Android and web can be built here. iOS source is included; building and signing iOS requires macOS/Xcode and Apple configuration.

## XAMPP web address

Run tool/publish-local-web.ps1 to build and copy the web app into the XAMPP app directory. Then open http://localhost/CoffeyTableRecipes/. This build works while Apache is running, without the Flutter development server. Republish after source changes.


For a phone connected through a hotspot or local Wi-Fi, open http://<laptop-IP>/CoffeyTableRecipes/app/. The page is served by the laptop, while authenticated requests use the hosted API. Republish after app source changes.

## Home screen design

The signed-in home opens directly to recipe search and the collection. The app bar avatar opens a standard user menu with account identity, Change name at the table, Change account display name, Household & people, and Log out. Account display names save to Firebase. Your name at the table updates your existing household member record, independently for each household; the same editor is available beside your own name in People at your table. Log out requires confirmation. The navigation menu opens Household & people for household selection, setup, and member management; returning to Recipes preserves the search. Signed-out users open the login form with Sign in. Artwork remains bundled for future branding use but is not shown on the home screen. The app retains its parchment, olive, coffee, and copper palette.

On mouse-only web devices, scrollable lists and photo strips use persistent, slim 7-pixel scrollbars with a muted olive thumb and no visible track. Drag the thumb or click its track area to navigate. Browsers reporting touch capability (including hybrid laptops) hide the bars and retain swipe scrolling. Native mobile scrolling is unchanged.

Recipe detail photos fit completely inside a frame no taller than 240 pixels or 30% of the viewport height. Distinct photos have previous/next buttons; WordPress size variants of the same photo display only once, with the selected cover retained. Orange Chicken's original and three resized variants therefore appear as one photo. Stored source references are preserved.

Imported recipe photos are downloaded and served from coffeybean.com under `CoffeyTableRecipes/media/recipe-photos/`. Photo records use the hosted URL and storage key; publisher URLs remain in the private import archive for provenance. See `recipe-import/HOSTED_IMPORT.md` for the archive and upload workflow.

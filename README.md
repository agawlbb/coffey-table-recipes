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

The home screen checks the actual API connection. Google authentication and household setup are implemented; recipes and meal-plan data are next. No simulated sign-in or development authorization bypass is provided.

See `docs/checkpoints.md` for the agreed implementation sequence and `docs/authentication.md` for configured sign-in commands. Default Flutter icons remain until the selected artwork is supplied.

## Platforms

Android and web can be built here. iOS source is included; building and signing iOS requires macOS/Xcode and Apple configuration.

## XAMPP web address

Run tool/publish-local-web.ps1 to build and copy the web app into the XAMPP app directory. Then open http://localhost/CoffeyTableRecipes/. This build works while Apache is running, without the Flutter development server. Republish after source changes.


For a phone connected through a hotspot or local Wi-Fi, open http://<laptop-IP>/CoffeyTableRecipes/app/. The page is served by the laptop, while health checks and authenticated requests use the hosted API. Republish after app source changes.

## Home screen design

The responsive home uses parchment surfaces, olive green, coffee brown, and copper accents. A welcome banner and prominent recipe collection card provide the main hierarchy; household members and member management are available in an expandable section. The connection indicator retains retry support without setup checkpoint copy. The supplied cookbook artwork is bundled locally in `assets/images/coffey_table.jpg` and displayed without cropping in a responsive welcome card.

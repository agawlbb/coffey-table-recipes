# Coffey Table Recipes

Flutter client for Android, iOS, and responsive web. The PHP API lives in `C:\xampp\htdocs\CoffeyTableRecipes`.

## Run locally

Start Apache and MySQL in XAMPP.

```powershell
flutter run -d emulator-5554
flutter run -d chrome --web-port=8080
```

Android emulator uses `http://10.0.2.2/CoffeyTableRecipes/api/v1`; web uses `http://localhost/CoffeyTableRecipes/api/v1`.

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


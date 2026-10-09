# Install on a physical Android phone

Build a signed local test APK from the project root. Replace `<computer-IP>` with the computer's current Wi-Fi IPv4 address:

```powershell
flutter build apk --debug --dart-define-from-file=config/firebase.local.json --dart-define=API_BASE_URL=http://<computer-IP>/CoffeyTableRecipes/api/v1
```

The installable file is `build/app/outputs/flutter-apk/app-debug.apk`. This universal APK supports the Android architectures included by Flutter. The debug build uses the existing debug signing identity registered with Firebase and permits HTTP to the local XAMPP server. Keep the APK, signing keys, and local Firebase configuration out of Git.

1. Copy the APK to your phone using USB, cloud storage, or another file transfer method.
2. Open the APK on the phone. If Android asks, allow that file manager or browser to install unknown apps, then install.
3. Open **Coffey Table Recipes**.
4. Keep Apache and MySQL running in XAMPP and connect the phone and computer to the same Wi-Fi or hotspot network.

On the phone, open `http://<computer-IP>/CoffeyTableRecipes/api/v1/health` in a browser to check connectivity. It should return JSON with `status` set to `ok`. If it cannot connect, check network isolation and the Windows firewall's Apache access on the current network.

The computer's IP address is embedded in this APK. Rebuild and transfer a new APK if that address changes. The app's backend requires the computer to remain reachable; this build is for local testing. A public deployment needs a reachable HTTPS backend and a production signing configuration.

If an existing app installation uses a different signing key, Android may require uninstalling it before this APK can be installed. Uninstalling clears local app data.

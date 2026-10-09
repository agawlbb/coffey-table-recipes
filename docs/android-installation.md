# Install on a physical Android phone

Build the signed local test APK from the project root:

```powershell
flutter build apk --debug --dart-define-from-file=config/firebase.local.json
```

The installable file is `build/app/outputs/flutter-apk/app-debug.apk`. It requires Android 7.0 or newer and includes ARM, ARM64, and x86_64 architectures. The debug build uses the existing signing identity registered with Firebase and permits HTTP to the local XAMPP server. Keep the APK, signing keys, and local Firebase configuration out of Git.

1. Transfer the APK to your phone, open it, allow that file manager or browser to install unknown apps if prompted, and install.
2. Keep Apache and MySQL running in XAMPP. Connect the phone and laptop to the same Wi-Fi or hotspot.
3. Find the laptop's current IP using the instructions below.
4. Open **Coffey Table Recipes**, expand **Debug: server address** at the top of the home screen, and enter `http://<laptop-IP>/CoffeyTableRecipes/api/v1`.
5. Tap **Save and apply**. The address is saved on the phone across app restarts; the home screen reloads and existing API clients are recreated. Firebase sign-in is retained.

When you change networks, update this field with the laptop's new IP. No rebuild or reinstall is required. Include `/CoffeyTableRecipes/api/v1`, and a port after the IP if Apache uses a nondefault port. You can also enter a full HTTPS API URL. The initial default is the Android emulator address `10.0.2.2`; replace it for a physical phone.

## Find the laptop's current IP

On Windows, press **Windows+R**, type `cmd`, and press Enter. Run:

```text
ipconfig
```

Under **Wireless LAN adapter Wi-Fi**, read **IPv4 Address**. Use the address for the adapter connected to the phone's network; ignore disconnected adapters, virtual adapters, the default gateway, and addresses beginning with `169.254`. If using Ethernet, read the connected Ethernet adapter instead.

Alternatively, open PowerShell and run:

```powershell
Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -eq 'Wi-Fi' } | Select-Object IPAddress
```

For example, if IPv4 Address is `172.20.10.2`, enter `http://172.20.10.2/CoffeyTableRecipes/api/v1` in the app.

To check reachability, open `http://<laptop-IP>/CoffeyTableRecipes/api/v1/health` in the phone's browser. Expect JSON with `status` set to `ok`. If it cannot connect, check the network's device isolation and Windows firewall access for Apache. Changing the app address does not make the laptop reachable from a separate network.

## Temporary tool and removal

This manual field is enabled only in native debug builds; web, profile, and release builds ignore the saved override. It does not open dialogs or react to connection failures. Invalid addresses show an inline error. The tool is isolated in `lib/src/debug_host.dart`: remove that file, its hooks in `lib/main.dart`, `lib/src/api.dart`, and `lib/src/app.dart`, its test, and the `shared_preferences` dependency when it is no longer needed. Restore `apiBaseUrl` to the build-defined/default URL and remove the `ValueListenableBuilder` wrapper and URL key in the app.

If an existing app installation uses a different signing key, Android may require uninstalling it before installing this APK. Uninstalling clears local app data. This local test build still needs the laptop running and reachable; public hosting requires its own server configuration and production signing setup.

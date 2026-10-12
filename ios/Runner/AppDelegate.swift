import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "RecipeShareInbox") {
      let channel = FlutterMethodChannel(name: "coffey_table_recipes/share_inbox", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        do {
          guard let group = Bundle.main.object(forInfoDictionaryKey: "AppGroupId") as? String,
                let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
            result(FlutterError(code: "share_group", message: "Recipe share storage is unavailable.", details: nil))
            return
          }
          if call.method == "pending" {
            let files = try FileManager.default.contentsOfDirectory(at: container, includingPropertiesForKeys: nil)
              .filter { $0.lastPathComponent.hasPrefix("RecipeShare-") && $0.pathExtension == "json" }
              .sorted { $0.lastPathComponent < $1.lastPathComponent }
            let payloads = try files.map { try JSONSerialization.jsonObject(with: Data(contentsOf: $0)) }
            result(payloads)
          } else if call.method == "acknowledge", let id = call.arguments as? String, UUID(uuidString: id) != nil {
            try FileManager.default.removeItem(at: container.appendingPathComponent("RecipeShare-\(id).json"))
            // Dart has copied the bytes. Only remove our UUID-named staging folder.
            try? FileManager.default.removeItem(at: container.appendingPathComponent("RecipeShare-\(id)", isDirectory: true))
            result(nil)
          } else { result(FlutterMethodNotImplemented) }
        } catch {
          result(FlutterError(code: "share_storage", message: "Could not read saved recipe shares.", details: nil))
        }
      }
    }
  }
}

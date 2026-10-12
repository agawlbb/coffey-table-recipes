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
          var containers = [try RecipeDocumentInbox.directory()]
          guard let group = Bundle.main.object(forInfoDictionaryKey: "AppGroupId") as? String,
                let shared = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
            throw NSError(domain: "RecipeShare", code: 1)
          }
          containers.append(shared)
          if call.method == "pending" {
            let files = try containers.flatMap {
              try FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)
            }
              .filter { $0.lastPathComponent.hasPrefix("RecipeShare-") && $0.pathExtension == "json" }
              .sorted { $0.lastPathComponent < $1.lastPathComponent }
            let payloads = try files.map { try JSONSerialization.jsonObject(with: Data(contentsOf: $0)) }
            result(payloads)
          } else if call.method == "acknowledge", let id = call.arguments as? String, UUID(uuidString: id) != nil {
            for container in containers {
              let manifest = container.appendingPathComponent("RecipeShare-\(id).json")
              if FileManager.default.fileExists(atPath: manifest.path) {
                try FileManager.default.removeItem(at: manifest)
                // Dart copied the bytes; only remove our UUID-named folder.
                try? FileManager.default.removeItem(at: container.appendingPathComponent("RecipeShare-\(id)", isDirectory: true))
              }
            }
            result(nil)
          } else { result(FlutterMethodNotImplemented) }
        } catch {
          result(FlutterError(code: "share_storage", message: "Could not read saved recipe shares.", details: nil))
        }
      }
      RecipeDocumentInbox.changed = { channel.invokeMethod("changed", arguments: nil) }
    }
  }
}

/// File-opening handoff uses the containing app's own sandbox, without App Groups.
enum RecipeDocumentInbox {
  static var changed: (() -> Void)?

  static func directory() throws -> URL {
    let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      .appendingPathComponent("RecipeDocumentInbox", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
  }

  static func receive(_ url: URL) {
    guard url.isFileURL else { return }
    let id = UUID().uuidString
    var staging: URL?
    do {
      let root = try directory()
      let folder = root.appendingPathComponent("RecipeShare-\(id)", isDirectory: true)
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      staging = folder
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
      guard size <= 5 * 1024 * 1024 else { throw DocumentError.tooLarge }
      var destination = folder.appendingPathComponent(url.lastPathComponent)
      if ["heic", "heif"].contains(url.pathExtension.lowercased()),
         let image = UIImage(contentsOfFile: url.path), let jpeg = image.jpegData(compressionQuality: 0.85) {
        guard jpeg.count <= 5 * 1024 * 1024 else { throw DocumentError.tooLarge }
        destination = destination.deletingPathExtension().appendingPathExtension("jpg")
        try jpeg.write(to: destination, options: .atomic)
      } else {
        try FileManager.default.copyItem(at: url, to: destination)
      }
      let payload: [String: Any] = ["id": id, "content": "", "attachments": [["path": destination.path]]]
      try JSONSerialization.data(withJSONObject: payload).write(to: root.appendingPathComponent("RecipeShare-\(id).json"), options: .atomic)
    } catch {
      if let staging { try? FileManager.default.removeItem(at: staging) }
      // Deliver an error notification, never an empty import screen.
      if let root = try? directory(),
         let data = try? JSONSerialization.data(withJSONObject: ["id": id, "attachments": [], "content": "", "error": error is DocumentError ? "Shared files must be at most 5 MB." : "Could not open the recipe file. Try Add recipe > Upload."]) {
        try? data.write(to: root.appendingPathComponent("RecipeShare-\(id).json"), options: .atomic)
      }
    }
    changed?()
  }

  private enum DocumentError: Error { case tooLarge }
}

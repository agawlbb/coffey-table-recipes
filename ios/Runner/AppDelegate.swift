import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    if notification.request.content.userInfo["kind"] as? String == "recipe_timer" {
      RecipeTimers.receivePush(notification.request.content.userInfo) { _ in completionHandler([.banner]) }
    }
    else if notification.request.content.userInfo["pendingSave"] as? Bool == true { completionHandler([.banner, .sound]) }
    else if notification.request.content.userInfo["recipeTimer"] as? Bool == true { completionHandler([.banner, .sound]) }
    else { super.userNotificationCenter(center, willPresent: notification, withCompletionHandler: completionHandler) }
  }

  override func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
    if userInfo["kind"] as? String == "recipe_timer" {
      RecipeTimers.receivePush(userInfo) { ok in completionHandler(ok ? .newData : .failed) }
    } else {
      super.application(application, didReceiveRemoteNotification: userInfo, fetchCompletionHandler: completionHandler)
    }
  }

  override func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
    if response.notification.request.content.userInfo["kind"] as? String == "recipe_timer" {
      RecipeTimers.receivePush(response.notification.request.content.userInfo) { _ in completionHandler() }
    } else {
      super.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PendingSaves") {
      let channel = FlutterMethodChannel(name: "coffey_table_recipes/pending_saves", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        guard call.method == "update" else { result(FlutterMethodNotImplemented); return }
        guard let args = call.arguments as? [String: Any], let scope = args["scope"] as? String,
              let changes = args["changes"] as? [[String: Any]] else {
          result(FlutterError(code: "pending_save", message: "Missing pending changes.", details: nil)); return
        }
        Task { @MainActor in
          do {
            let center = UNUserNotificationCenter.current()
            // Account identifiers remain in private preferences, not notification text.
            let stateKey = "pendingSaveReminders:" + scope
            let previous = UserDefaults.standard.dictionary(forKey: stateKey) as? [String: String] ?? [:]
            var next: [String: String] = [:]
            let due = changes.compactMap { $0["deadline"] as? NSNumber }.map { $0.doubleValue }.min()
            // One account reminder avoids the OS limit on pending notifications.
            if let due = due {
              let version = String(due)
              if let existing = previous[version] { next[version] = existing }
              else {
                guard try await center.requestAuthorization(options: [.alert, .sound]) else {
                  throw NSError(domain: "PendingSaves", code: 1, userInfo: [NSLocalizedDescriptionKey: "Allow notifications in device settings."])
                }
                let id = "pending-save-" + UUID().uuidString
                let content = UNMutableNotificationContent()
                content.title = "Changes waiting to sync"
                content.body = "Saved on this device, but the server has not confirmed a change after one minute. Open Coffey Table Recipes to check synchronization."
                content.sound = .default
                content.userInfo = ["pendingSave": true]
                let delay = max(1, due / 1000 - Date().timeIntervalSince1970)
                try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)))
                next[version] = id
              }
            }
            let removed = previous.filter { next[$0.key] == nil }.map { $0.value }
            center.removePendingNotificationRequests(withIdentifiers: removed)
            center.removeDeliveredNotifications(withIdentifiers: removed)
            UserDefaults.standard.set(next, forKey: stateKey)
            result(nil)
          } catch { result(FlutterError(code: "pending_save", message: error.localizedDescription, details: nil)) }
        }
      }
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "RecipeTimers") {
      RecipeTimers.register(registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "RecipeLinkShare") {
      let channel = FlutterMethodChannel(name: "coffey_table_recipes/share_link", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        guard call.method == "share" else { result(FlutterMethodNotImplemented); return }
        guard let args = call.arguments as? [String: Any],
              let html = args["html"] as? String,
              let text = args["text"] as? String,
              let title = args["title"] as? String else {
          result(FlutterError(code: "invalid_link", message: "Missing recipe link.", details: nil)); return
        }
        DispatchQueue.main.async {
          guard var presenter = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows }).first(where: { $0.isKeyWindow })?.rootViewController else {
            result(FlutterError(code: "share_unavailable", message: "Could not open sharing.", details: nil)); return
          }
          while let presented = presenter.presentedViewController { presenter = presented }
          let item = RecipeLinkShareItem(html: html, text: text, title: title)
          let sheet = UIActivityViewController(activityItems: [item], applicationActivities: nil)
          if let popover = sheet.popoverPresentationController {
            popover.sourceView = presenter.view
            if let rect = args["origin"] as? [Double], rect.count == 4 {
              popover.sourceRect = CGRect(x: rect[0], y: rect[1], width: rect[2], height: rect[3])
            } else {
              popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
            }
          }
          presenter.present(sheet, animated: true) { result(true) }
        }
      }
    }
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

/// Mail accepts an HTML body; other activities retain a readable name and URL.
final class RecipeLinkShareItem: NSObject, UIActivityItemSource {
  let html: String
  let text: String
  let title: String
  init(html: String, text: String, title: String) {
    self.html = html; self.text = text; self.title = title
    super.init()
  }
  func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any { text }
  func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
    activityType == .mail ? Data(html.utf8) as Any : text as Any
  }
  func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String {
    activityType == .mail ? "public.html" : "public.utf8-plain-text"
  }
  func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String { title }
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

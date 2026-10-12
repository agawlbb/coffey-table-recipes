import UIKit
import UniformTypeIdentifiers
import WebKit

/// Imports within the share sheet, without App Groups or containing-app launch.
final class ShareViewController: UIViewController, WKScriptMessageHandler, WKNavigationDelegate {
  private var web: WKWebView!
  private var token: String?
  private var working = false
  private let session = URLSession(configuration: .ephemeral)
  private let limit = 5 * 1024 * 1024

  override func viewDidLoad() {
    super.viewDidLoad()
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.userContentController.add(self, name: "recipeShare")
    web = WKWebView(frame: .zero, configuration: configuration)
    web.navigationDelegate = self
    web.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(web)
    NSLayoutConstraint.activate([
      web.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
      web.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      web.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      web.trailingAnchor.constraint(equalTo: view.trailingAnchor)
    ])
    guard let page = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "ShareUI") else {
      let label = UILabel(frame: view.bounds)
      label.text = "Recipe sharing could not load. Please reinstall the app."
      label.numberOfLines = 0
      view.addSubview(label)
      return
    }
    web.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    if view.window == nil {
      token = nil
      session.invalidateAndCancel()
      web.configuration.userContentController.removeScriptMessageHandler(forName: "recipeShare")
    }
  }

  func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
               decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    decisionHandler(navigationAction.request.url?.isFileURL == true ? .allow : .cancel)
  }

  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    guard message.frameInfo.isMainFrame, message.frameInfo.request.url?.isFileURL == true,
          let body = message.body as? [String: Any], let id = body["id"] as? Int,
          let action = body["action"] as? String else { return }
    if action == "close" {
      token = nil
      session.invalidateAndCancel()
      web.configuration.userContentController.removeScriptMessageHandler(forName: "recipeShare")
      extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
      return
    }
    if working { reply(id, error: "Wait for the current request to finish."); return }
    working = true
    Task { @MainActor in
      defer { working = false }
      do {
        let value: Any
        switch action {
        case "read":
          value = try await readShare()
        case "signIn":
          guard let email = body["email"] as? String, let password = body["password"] as? String,
                !email.isEmpty, !password.isEmpty else { throw failure("Enter your email and password.") }
          guard let file = Bundle.main.url(forResource: "FirebaseConfig", withExtension: "json", subdirectory: "ShareUI"),
                let config = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: String],
                let key = config["apiKey"], !key.isEmpty,
                let url = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=\(key)") else {
            throw failure("Sign-in configuration is missing. Please reinstall an updated build.")
          }
          let auth = try await request(url, body: ["email": email, "password": password, "returnSecureToken": true])
          guard let newToken = auth["idToken"] as? String else { throw failure("Could not sign in.") }
          token = newToken
          value = try await api("/me")
        case "analyze", "save":
          guard let household = body["household"] as? String,
                household.range(of: "^[1-9][0-9]{0,18}$", options: .regularExpression) != nil,
                let input = body["body"] as? [String: Any] else { throw failure("Choose your table first.") }
          value = try await api("/households/\(household)/\(action == "save" ? "recipes" : "recipe-import")", body: input)
        default: throw failure("Unknown sharing action.")
        }
        reply(id, value: value)
      } catch { reply(id, error: error.localizedDescription) }
    }
  }

  private func reply(_ id: Int, value: Any = NSNull(), error: String? = nil) {
    web.callAsyncJavaScript("window.recipeShareReply(id, value, error)",
      arguments: ["id": id, "value": value, "error": error as Any? ?? NSNull()],
      in: nil, in: .page, completionHandler: nil)
  }

  private func failure(_ message: String) -> NSError {
    NSError(domain: "RecipeShare", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }

  private func api(_ path: String, body: [String: Any]? = nil) async throws -> [String: Any] {
    guard let token else { throw failure("Sign in to import the recipe.") }
    return try await request(URL(string: "https://coffeybean.com/CoffeyTableRecipes/api/v1\(path)")!, body: body, bearer: token,
                             saving: path.hasSuffix("/recipes") && body != nil)
  }

  private func request(_ url: URL, body: [String: Any]?, bearer: String? = nil, saving: Bool = false) async throws -> [String: Any] {
    let unknownSave = "Save outcome unknown. Check your table in the app before sharing again."
    var request = URLRequest(url: url)
    request.timeoutInterval = 150
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if url.host == "identitytoolkit.googleapis.com" {
      request.setValue(Bundle.main.bundleIdentifier, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
    }
    if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
    if let body {
      request.httpMethod = "POST"
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
    }
    let data: Data
    let response: URLResponse
    do { (data, response) = try await session.data(for: request) }
    catch { throw failure(saving ? unknownSave : "Could not connect. Your input is still here; try again.") }
    guard let http = response as? HTTPURLResponse,
          let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw failure(saving ? unknownSave : "The server returned an unreadable response. Try again.")
    }
    guard (200..<300).contains(http.statusCode) else {
      if saving && http.statusCode >= 500 { throw failure(unknownSave) }
      let details = result["error"] as? [String: Any]
      let message = details?["message"] as? String ?? "The request failed. Try again."
      if url.host == "identitytoolkit.googleapis.com" {
        throw failure("Could not sign in. Check your email and password. For a Google-only account, set an email password using Forgot password in the app.")
      }
      if http.statusCode == 401 { token = nil; throw failure("Your sign-in expired. Cancel and share again to sign in.") }
      throw failure(message)
    }
    return result
  }

  private func readShare() async throws -> [[String: Any]] {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("RecipeShare-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    var files: [[String: Any]] = []
    var texts: [String] = []
    var total = 0
    for item in extensionContext?.inputItems.compactMap({ $0 as? NSExtensionItem }) ?? [] {
      for provider in item.attachments ?? [] {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) &&
            !provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
          let value = try await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil)
          guard let url = value as? URL else { throw failure("Could not read the shared file.") }
          let scoped = url.startAccessingSecurityScopedResource()
          defer { if scoped { url.stopAccessingSecurityScopedResource() } }
          files.append(try fileInput(copyFile(url, folder: folder), total: &total))
        } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) ||
                    provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) ||
                    (!provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) &&
                     !provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) &&
                     provider.hasItemConformingToTypeIdentifier(UTType.data.identifier)) {
          let type = provider.registeredTypeIdentifiers.first(where: {
            UTType($0)?.conforms(to: .data) == true && $0 != UTType.fileURL.identifier
          }) ?? UTType.data.identifier
          let copied: URL = try await withCheckedThrowingContinuation { continuation in
            // Copy before the callback returns; iOS removes the source afterwards.
            provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
              do {
                if let error { throw error }
                guard let url else { throw self.failure("Could not read the shared file.") }
                continuation.resume(returning: try self.copyFile(url, folder: folder))
              } catch { continuation.resume(throwing: error) }
            }
          }
          files.append(try fileInput(copied, total: &total))
        } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
          let value = try await provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil)
          if let url = value as? URL { texts.append(url.absoluteString) }
          else if let text = value as? String { texts.append(text) }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
          let value = try await provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil)
          if let text = value as? String { texts.append(text) }
          else if let data = value as? Data, let text = String(data: data, encoding: .utf8) { texts.append(text) }
        }
        guard files.count <= 10 else { throw failure("Share at most 10 files at a time.") }
      }
    }
    // Captions must not become extra recipes alongside attachments.
    if !files.isEmpty { return files }
    let text = texts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { throw failure("Share a PDF, image, recipe text, or website link.") }
    guard text.utf8.count <= 60000 else { throw failure("Share at most 60,000 bytes of recipe text.") }
    if let url = URL(string: text), url.scheme == "https", url.host != nil {
      return [["name": "Website recipe", "body": ["kind": "website", "url": text]]]
    }
    return [["name": "Shared recipe text", "body": ["kind": "text", "input_source": "pasted_text", "text": text]]]
  }

  private func fileInput(_ url: URL, total: inout Int) throws -> [String: Any] {
    guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= limit else {
      throw failure("Shared files must be at most 5 MB.")
    }
    let data = try Data(contentsOf: url)
    total += data.count
    guard total <= 10 * 1024 * 1024 else { throw failure("Share up to 10 MB in total, or share the files separately.") }
    if url.pathExtension.lowercased() == "txt" {
      guard let text = String(data: data, encoding: .utf8) else { throw failure("Text files must use UTF-8.") }
      guard data.count <= 60000 else { throw failure("Share at most 60,000 bytes of recipe text.") }
      return ["name": url.lastPathComponent, "body": ["kind": "text", "input_source": "uploaded_text", "text": text]]
    }
    return ["name": url.lastPathComponent, "body": ["kind": "file", "file_base64": data.base64EncodedString()]]
  }

  private func copyFile(_ url: URL, folder: URL) throws -> URL {
    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    guard size <= limit else { throw failure("Shared files must be at most 5 MB.") }
    let subfolder = folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)
    let destination = subfolder.appendingPathComponent(url.lastPathComponent.isEmpty ? "recipe" : url.lastPathComponent)
    if ["heic", "heif"].contains(url.pathExtension.lowercased()),
       let image = UIImage(contentsOfFile: url.path), let jpeg = image.jpegData(compressionQuality: 0.85) {
      guard jpeg.count <= limit else { throw failure("Shared files must be at most 5 MB.") }
      let converted = destination.deletingPathExtension().appendingPathExtension("jpg")
      try jpeg.write(to: converted, options: .atomic)
      return converted
    }
    try FileManager.default.copyItem(at: url, to: destination)
    return destination
  }
}

import UIKit
import UniformTypeIdentifiers

/// Persist shares without depending on an unsupported launch of the containing app.
final class ShareViewController: UIViewController {
  private let status = UILabel()
  private let done = UIButton(type: .system)
  private var started = false

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    status.numberOfLines = 0
    status.textAlignment = .center
    status.text = "Preparing recipe import…"
    done.setTitle("Done", for: .normal)
    done.isHidden = true
    done.addTarget(self, action: #selector(finish), for: .touchUpInside)
    let stack = UIStackView(arrangedSubviews: [status, done])
    stack.axis = .vertical
    stack.spacing = 24
    stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
      stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)
    ])
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    guard !started else { return }
    started = true
    Task { await saveShare() }
  }

  @objc private func finish() {
    extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
  }

  private func saveShare() async {
    var staging: URL?
    do {
      guard let group = Bundle.main.object(forInfoDictionaryKey: "AppGroupId") as? String,
            let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
        throw ShareError.message("Recipe sharing is unavailable. The app and share extension must be signed with the same App Group.")
      }
      let id = UUID().uuidString
      let folder = container.appendingPathComponent("RecipeShare-\(id)", isDirectory: true)
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      staging = folder
      var attachments: [[String: String]] = []
      var texts: [String] = []
      for item in extensionContext?.inputItems.compactMap({ $0 as? NSExtensionItem }) ?? [] {
        for provider in item.attachments ?? [] {
          if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) &&
              !provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            let value = try await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil)
            guard let url = value as? URL else { throw ShareError.message("Could not read the shared file.") }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let path = try copyFile(url, folder: folder)
            attachments.append(["path": path, "type": "file"])
          } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) ||
              provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) ||
              (!provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) &&
               !provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) &&
               provider.hasItemConformingToTypeIdentifier(UTType.data.identifier)) {
            let type = provider.registeredTypeIdentifiers.first(where: {
              UTType($0)?.conforms(to: .data) == true && $0 != UTType.fileURL.identifier
            }) ?? UTType.data.identifier
            let path = try await copyRepresentation(provider, type: type, folder: folder)
            attachments.append(["path": path, "type": "file"])
          } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            let value = try await provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil)
            if let url = value as? URL { texts.append(url.absoluteString) }
          } else if provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
            let value = try await provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil)
            if let text = value as? String { texts.append(text) }
            else if let data = value as? Data, let text = String(data: data, encoding: .utf8) { texts.append(text) }
          }
        }
      }
      guard !attachments.isEmpty || !texts.isEmpty else {
        throw ShareError.message("This item could not be read. Try sharing a PDF, image, recipe text or website link.")
      }
      let payload: [String: Any] = ["id": id, "attachments": attachments, "content": texts.joined(separator: "\n")]
      let data = try JSONSerialization.data(withJSONObject: payload)
      try data.write(to: container.appendingPathComponent("RecipeShare-\(id).json"), options: .atomic)
      status.text = "Ready to import. Open Coffey Table Recipes to review your recipe."
    } catch {
      if let staging { try? FileManager.default.removeItem(at: staging) }
      status.text = (error as? ShareError)?.description ?? "Could not read the shared item. Try downloading it first and sharing it again."
    }
    done.isHidden = false
  }

  private func copyRepresentation(_ provider: NSItemProvider, type: String, folder: URL) async throws -> String {
    try await withCheckedThrowingContinuation { continuation in
      // Copy before this callback returns: iOS then removes the temporary file.
      provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
        do {
          if let error { throw error }
          guard let url else { throw ShareError.message("Could not read the shared file.") }
          continuation.resume(returning: try self.copyFile(url, folder: folder))
        } catch { continuation.resume(throwing: error) }
      }
    }
  }

  private func copyFile(_ url: URL, folder: URL) throws -> String {
    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    guard size <= 5 * 1024 * 1024 else { throw ShareError.message("Shared files must be at most 5 MB.") }
    let name = url.lastPathComponent.isEmpty ? "recipe" : url.lastPathComponent
    let destination = folder.appendingPathComponent(UUID().uuidString + "-" + name)
    if ["heic", "heif"].contains(url.pathExtension.lowercased()),
       let image = UIImage(contentsOfFile: url.path), let jpeg = image.jpegData(compressionQuality: 0.85) {
      guard jpeg.count <= 5 * 1024 * 1024 else { throw ShareError.message("Shared files must be at most 5 MB.") }
      let converted = destination.deletingPathExtension().appendingPathExtension("jpg")
      try jpeg.write(to: converted, options: .atomic)
      return converted.path
    }
    try FileManager.default.copyItem(at: url, to: destination)
    return destination.path
  }

  private enum ShareError: Error {
    case message(String)
    var description: String { switch self { case .message(let value): return value } }
  }
}

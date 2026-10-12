import UIKit

// Test-only host: invokes the system share sheet with sample input, never the API.
@main
final class ProbeApp: UIResponder, UIApplicationDelegate {
  var window: UIWindow?
  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    window = UIWindow(frame: UIScreen.main.bounds)
    window?.rootViewController = ProbeController()
    window?.makeKeyAndVisible()
    return true
  }
}

final class ProbeController: UIViewController {
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    let stack = UIStackView()
    stack.axis = .vertical
    stack.spacing = 24
    for name in ["Share PDF", "Share text"] {
      let button = UIButton(type: .system)
      button.setTitle(name, for: .normal)
      button.accessibilityIdentifier = name
      button.addAction(UIAction { [weak self] _ in self?.share(pdf: name == "Share PDF") }, for: .touchUpInside)
      stack.addArrangedSubview(button)
    }
    stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
    ])
  }
  private func share(pdf: Bool) {
    let input: Any
    if pdf {
      let file = FileManager.default.temporaryDirectory.appendingPathComponent("share-launch-sample.pdf")
      let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
      do {
        try renderer.writePDF(to: file) { context in
          context.beginPage()
          "Test recipe: 2 limes. Bake for 25 minutes.".draw(at: CGPoint(x: 30, y: 30), withAttributes: nil)
        }
      } catch { fatalError("Could not create the test PDF") }
      input = file
    } else { input = "Test recipe: 2 limes. Bake for 25 minutes." }
    let sheet = UIActivityViewController(activityItems: [input], applicationActivities: nil)
    sheet.popoverPresentationController?.sourceView = view
    present(sheet, animated: true)
  }
}

import XCTest

final class ShareLaunchTests: XCTestCase {
  override func setUp() { continueAfterFailure = false }

  @MainActor
  func testPDFShareLaunchesImporterAndCancelReturnsToHost() {
    checkShare("Share PDF")
  }

  @MainActor
  func testTextShareLaunchesImporterAndCancelReturnsToHost() {
    checkShare("Share text")
  }

  @MainActor
  private func checkShare(_ input: String) {
    let host = XCUIApplication()
    host.launch()
    let share = host.buttons[input]
    XCTAssertTrue(share.waitForExistence(timeout: 20))
    share.tap()
    capture(host, name: "System share sheet - \(input)")

    var choice = activity(host, named: "Coffey Table Recipes")
    if !choice.waitForExistence(timeout: 5) || !choice.isHittable {
      let more = activity(host, named: "More")
      if more.exists && more.isHittable { more.tap() }
      choice = activity(host, named: "Coffey Table Recipes")
    }
    capture(host, name: "Extension selection - \(input)")
    XCTAssertTrue(choice.waitForExistence(timeout: 15), "Extension missing from share sheet: \(host.debugDescription)")
    choice.tap()

    // Native read -> WKWebView -> JS reply must complete before sign-in appears.
    let signIn = host.webViews.buttons["Sign in"].firstMatch
    let opened = signIn.waitForExistence(timeout: 45)
    capture(host, name: "Importer launch - \(input)")
    XCTAssertTrue(opened, "Importer did not open: \(host.debugDescription)")
    XCTAssertTrue(host.webViews.textFields["Email"].exists)
    XCTAssertTrue(host.webViews.secureTextFields["Password"].exists)
    let email = host.webViews.textFields["Email"].firstMatch
    email.tap()
    email.typeText("share-test@example.invalid")
    XCTAssertEqual(email.value as? String, "share-test@example.invalid")
    capture(host, name: "Interactive importer - \(input)")
    host.webViews.buttons["Cancel"].firstMatch.tap()
    XCTAssertTrue(share.waitForExistence(timeout: 15))
  }

  @MainActor
  private func activity(_ app: XCUIApplication, named title: String) -> XCUIElement {
    // File shares can expose activities as Cells; text shares can use Buttons.
    // Match either role instead of mistaking a visible icon for a missing extension.
    let cells = app.cells.matching(identifier: title).firstMatch
    if cells.exists { return cells }
    let buttons = app.buttons.matching(identifier: title).firstMatch
    if buttons.exists { return buttons }
    return app.staticTexts.matching(identifier: title).firstMatch
  }

  @MainActor
  private func capture(_ app: XCUIApplication, name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}

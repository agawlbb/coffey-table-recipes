import XCTest

final class ShareLaunchTests: XCTestCase {
  override func setUp() { continueAfterFailure = false }

  @MainActor
  func testPDFSharePersistsAndDoneReturnsToHost() {
    checkShare("Share PDF")
  }

  @MainActor
  func testTextSharePersistsAndDoneReturnsToHost() {
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

    // The receiver atomically persists the share before announcing success.
    let ready = host.staticTexts["Ready to import. Open Coffey Table Recipes to review your recipe."]
    let opened = ready.waitForExistence(timeout: 45)
    capture(host, name: "Receiver launch - \(input)")
    XCTAssertTrue(opened, "Receiver did not open: \(host.debugDescription)")
    XCTAssertEqual(host.webViews.count, 0)
    host.buttons["Done"].firstMatch.tap()
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

import XCTest

/// 在独立临时保险库中覆盖添加、复制、搜索和编辑的用户流程。
internal final class TickKeyUITests: XCTestCase {
  /// 验证侧边抽屉推开主界面、点击遮罩复位及图片选择器可取消。
  @MainActor
  func testSettingsDrawerAndPhotoPicker() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing", "-AppleLanguages", "(en)"]
    app.launch()
    let addButton = app.buttons["add-account"]
    let originalFrame = addButton.frame
    app.buttons["Settings"].tap()
    let close = app.buttons["close-settings"]
    XCTAssertTrue(close.waitForExistence(timeout: 5))
    let dimming = app.otherElements["dismiss-settings"]
    XCTAssertGreaterThan(dimming.frame.minX, app.frame.width * 0.7)
    let screen = XCTAttachment(screenshot: app.screenshot())
    screen.name = "Settings drawer"
    screen.lifetime = .keepAlways
    add(screen)
    dimming.tap()
    XCTAssertTrue(addButton.waitForExistence(timeout: 3))
    XCTAssertEqual(addButton.frame.minX, originalFrame.minX, accuracy: 1)
    app.buttons["Settings"].tap()
    close.tap()
    addButton.tap()
    app.buttons["Import from photos"].tap()
    XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
    app.buttons["Cancel"].tap()
    XCTAssertTrue(addButton.waitForExistence(timeout: 3))
  }

  /// 测试使用虚构账户，并保留关键页面截图供布局验收。
  @MainActor

  func testAddSearchAndEdit() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing", "-AppleLanguages", "(en)"]
    app.launch()
    app.buttons["add-account"].tap()
    app.buttons["Enter manually"].tap()
    XCTAssertTrue(app.textFields["issuer"].waitForExistence(timeout: 5))
    app.textFields["issuer"].tap()
    let form = XCTAttachment(screenshot: app.screenshot())
    form.name = "Account editor"
    form.lifetime = .keepAlways
    add(form)
    app.textFields["issuer"].typeText("GitHub")
    app.textFields["account"].tap()
    app.textFields["account"].typeText("alice@example.com")
    app.secureTextFields["secret"].tap()
    app.secureTextFields["secret"].typeText("JBSWY3DPEHPK3PXP")
    app.buttons["save-account"].tap()
    XCTAssertTrue(app.cells["token-alice@example.com"].waitForExistence(timeout: 5))
    let screen = XCTAttachment(screenshot: app.screenshot())
    screen.name = "Accounts"
    screen.lifetime = .keepAlways
    add(screen)
    app.cells["token-alice@example.com"].tap()
    XCTAssertTrue(app.staticTexts["Copied · clears in 30 seconds"].waitForExistence(timeout: 3))
    let search = app.searchFields.firstMatch
    search.tap()
    search.typeText("no-such-account")
    XCTAssertTrue(app.staticTexts["No matching accounts"].waitForExistence(timeout: 3))
    search.buttons.firstMatch.tap()
    app.buttons["Cancel"].tap()
    app.buttons["Edit alice@example.com"].tap()
    app.buttons["Edit"].tap()
    XCTAssertEqual(app.textFields["account"].value as? String, "alice@example.com")
    app.buttons["Cancel"].tap()
  }
}

import XCTest

// MARK: - TickKeyUITests

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
    // 部分模拟器会额外弹出系统密码保存面板；测试账户不保存到系统密码库。
    let savePassword = app.sheets["保存密码？"]
    if savePassword.exists {
      savePassword.buttons["以后"].tap()
    }
    XCTAssertTrue(app.staticTexts["GitHub · alice@example.com"].exists)
    XCTAssertLessThan(app.cells["token-alice@example.com"].frame.height, 100)
    let screen = XCTAttachment(screenshot: app.screenshot())
    screen.name = "Accounts"
    screen.lifetime = .keepAlways
    add(screen)
    verifyCopyHUD(app)
    let search = app.searchFields.firstMatch
    search.tap()
    search.typeText("no-such-account")
    XCTAssertTrue(app.staticTexts["No matching accounts"].waitForExistence(timeout: 3))
    search.buttons.firstMatch.tap()
    let cancelSearch = app.buttons
      .matching(NSPredicate(format: "label ==[c] 'Cancel' OR label ==[c] 'Close'"))
      .firstMatch
    cancelSearch.tap()
    app.cells["token-alice@example.com"].swipeLeft()
    app.buttons["Edit"].tap()
    XCTAssertEqual(app.textFields["account"].value as? String, "alice@example.com")
    app.buttons["Cancel"].tap()
    // 覆盖原先未进入过的二维码导出页面，防止视图约束异常逃过核心编码测试。
    app.buttons["Export"].tap()
    app.buttons["Account QR codes"].tap()
    XCTAssertTrue(app.images["export-qr-image"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["1 / 1"].exists)
    XCTAssertFalse(app.buttons["next-qr"].isEnabled)
    app.buttons["Close"].tap()
    app.cells["token-alice@example.com"].swipeLeft()
    let menu = XCTAttachment(screenshot: app.screenshot())
    menu.name = "Account swipe actions"
    menu.lifetime = .keepAlways
    add(menu)
    app.buttons["Show QR code"].tap()
    XCTAssertTrue(app.images["export-qr-image"].waitForExistence(timeout: 5))
    app.buttons["Close"].tap()
    verifyFileExports(app)
    verifySwipeDeletion(app)
  }

  /// 复制提示覆盖内容但不移动账户行，连续点击不会叠加提示，且会自动消失。
  @MainActor
  private func verifyCopyHUD(_ app: XCUIApplication) {
    let cell = app.cells["token-alice@example.com"]
    let frame = cell.frame
    cell.tap()
    let hud = app.otherElements["copy-hud"]
    XCTAssertTrue(hud.waitForExistence(timeout: 3))
    XCTAssertEqual(cell.frame, frame)
    let screen = XCTAttachment(screenshot: app.screenshot())
    screen.name = "Copy HUD"
    screen.lifetime = .keepAlways
    add(screen)
    cell.tap()
    XCTAssertTrue(hud.waitForExistence(timeout: 3))
    XCTAssertEqual(app.otherElements.matching(identifier: "copy-hud").count, 1)
    XCTAssertTrue(hud.waitForNonExistence(timeout: 5))
    XCTAssertEqual(cell.frame, frame)
  }

  /// 左滑只展开菜单，取消删除保持账户，确认后才真正移除。
  @MainActor
  private func verifySwipeDeletion(_ app: XCUIApplication) {
    let cell = app.cells["token-alice@example.com"]
    cell.swipeLeft()
    app.buttons["Delete"].tap()
    let confirmation = app.alerts["Delete"]
    XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
    confirmation.buttons["Cancel"].tap()
    XCTAssertTrue(cell.exists)
    cell.swipeLeft()
    app.buttons["Delete"].tap()
    confirmation.buttons["Continue"].tap()
    // UITableView 的复用缓存可能仍出现在 XCTest 层级中，按实际空态验证删除结果。
    XCTAssertTrue(app.staticTexts["Your keys, in one place"].waitForExistence(timeout: 5))
    let empty = XCTAttachment(screenshot: app.screenshot())
    empty.name = "Accounts after deletion"
    empty.lifetime = .keepAlways
    add(empty)
  }

  /// 编码、文件写入和密码弹窗衔接完成后应打开文件面板；测试取消保存以免写入用户目录。
  @MainActor
  private func verifyFileExports(_ app: XCUIApplication) {
    app.buttons["Export"].tap()
    app.buttons["Plain text (.txt)"].tap()
    let warning = app.alerts["Plain text (.txt)"]
    XCTAssertTrue(warning.waitForExistence(timeout: 5))
    warning.buttons["Continue"].tap()
    dismissFileExport(app)
    app.buttons["Export"].tap()
    app.buttons["Encrypted backup (.tickkey)"].tap()
    let password = app.secureTextFields.element(boundBy: 0)
    XCTAssertTrue(password.waitForExistence(timeout: 5))
    password.tap()
    password.typeText("Test-backup-password-2026")
    let confirmation = app.secureTextFields.element(boundBy: 1)
    confirmation.tap()
    confirmation.typeText("Test-backup-password-2026")
    app.buttons["Continue"].tap()
    dismissFileExport(app)
  }

  /// 系统文件面板的取消控件在部分 SDK/运行时组合下没有 button 语义，使用下拉关闭。
  @MainActor
  private func dismissFileExport(_ app: XCUIApplication) {
    XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 15))
    let navigation = app.navigationBars["FullDocumentManagerViewControllerNavigationBar"]
    navigation.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05))
      .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)))
    XCTAssertTrue(app.buttons["add-account"].waitForExistence(timeout: 5))
  }
}

/// 使用独立的七个虚构账户验证选择与两次确认，测试启动不会读写真实保险库。
extension TickKeyUITests {
  @MainActor
  private func launchSelectionFixture() -> XCUIApplication {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing", "--ui-testing-selection", "-AppleLanguages", "(en)"]
    app.launch()
    XCTAssertTrue(app.cells["token-test-1"].waitForExistence(timeout: 5))
    app.buttons["select-accounts"].tap()
    return app
  }

  @MainActor
  func testBatchDeletionRequiresTwoConfirmationsAboveFive() {
    let app = launchSelectionFixture()
    let delete = app.buttons["delete-selected-accounts"]
    XCTAssertFalse(delete.isEnabled)
    app.buttons["select-all-accounts"].tap()
    app.buttons["invert-account-selection"].tap()
    XCTAssertFalse(delete.isEnabled)
    app.buttons["select-all-accounts"].tap()
    app.cells["token-test-1"].tap()
    delete.tap()
    let first = app.alerts["Delete selected accounts?"]
    XCTAssertTrue(first.waitForExistence(timeout: 3))
    XCTAssertTrue(first.staticTexts
      .containing(NSPredicate(format: "label CONTAINS 'Selected accounts: 6'"))
      .firstMatch
      .exists)
    first.buttons["Cancel"].tap()
    XCTAssertTrue(app.cells["token-test-2"].exists)
    delete.tap()
    first.buttons["Continue"].tap()
    let final = app.alerts["Confirm permanent deletion"]
    XCTAssertTrue(final.waitForExistence(timeout: 3))
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "Batch deletion second confirmation"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    final.buttons["Cancel"].tap()
    XCTAssertTrue(app.cells["token-test-2"].exists)
    delete.tap()
    first.buttons["Continue"].tap()
    XCTAssertTrue(final.waitForExistence(timeout: 3))
    final.buttons["Delete permanently"].tap()
    XCTAssertTrue(app.buttons["select-accounts"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.cells["token-test-1"].exists)
    XCTAssertFalse(app.cells["token-test-2"].exists)
    app.terminate()
  }

  @MainActor
  func testPartialBatchDeletionUsesOneConfirmation() {
    let app = launchSelectionFixture()
    app.cells["token-test-1"].tap()
    app.cells["token-test-2"].tap()
    XCTAssertFalse(app.otherElements["copy-hud"].exists)
    app.buttons["delete-selected-accounts"].tap()
    let first = app.alerts["Delete selected accounts?"]
    XCTAssertTrue(first.waitForExistence(timeout: 3))
    first.buttons["Delete permanently"].tap()
    XCTAssertTrue(app.buttons["select-accounts"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.alerts["Confirm permanent deletion"].exists)
    XCTAssertTrue(app.cells["token-test-3"].exists)
    XCTAssertFalse(app.cells["token-test-1"].exists)
  }

  @MainActor
  func testFilteredSelectAllRequiresTwoConfirmationsForOneAccount() {
    let app = launchSelectionFixture()
    let search = app.searchFields.firstMatch
    search.tap()
    search.typeText("test-1\n")
    XCTAssertTrue(app.cells["token-test-2"].waitForNonExistence(timeout: 5))
    app.buttons["select-all-accounts"].tap()
    app.buttons["delete-selected-accounts"].tap()
    let first = app.alerts["Delete selected accounts?"]
    XCTAssertTrue(first.waitForExistence(timeout: 3))
    XCTAssertTrue(first.staticTexts
      .containing(NSPredicate(format: "label CONTAINS 'Selected accounts: 1'"))
      .firstMatch
      .exists)
    first.buttons["Continue"].tap()
    let final = app.alerts["Confirm permanent deletion"]
    XCTAssertTrue(final.waitForExistence(timeout: 3))
    final.buttons["Delete permanently"].tap()
    // 完成删除退出搜索和多选后，其余六个隐藏账户必须仍然存在。
    XCTAssertTrue(app.cells["token-test-2"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.cells["token-test-1"].exists)
    XCTAssertEqual(app.cells.count, 6)
  }
}

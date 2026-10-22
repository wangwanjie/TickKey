import ImageIO
import XCTest
#if os(macOS)
  import AppKit
  @testable import TickKeyMac
#else
  @testable import TickKey
#endif

// MARK: - CoreTests

/// 使用公开样例验证算法、备份协议、身份比较和事务持久化。
internal final class CoreTests: XCTestCase {
  /// 去重只影响展示，保留真实账户中的相似前缀、邮箱和原始身份。
  func testDisplayNameDeduplicatesOnlyCompleteIssuerPrefixes() throws {
    let examples = [
      ("OpenList", "OpenList:VanJay", "OpenList · VanJay"),
      ("OpenList", " openlist : OpenList：VanJay ", "OpenList · VanJay"),
      ("Gate", "Gate:", "Gate"),
      ("Gate", "gate", "Gate"),
      ("Gate", "", "Gate"),
      ("", "alice@example.com", "alice@example.com"),
      ("GitHub", "GitHubber", "GitHub · GitHubber"),
      ("GitHub", "GitHub@example.com", "GitHub · GitHub@example.com"),
      ("GitHub", "alice:GitHub", "GitHub · alice:GitHub"),
      ("公司: A", "公司: A:账户", "公司: A · 账户")
    ]
    for (issuer, account, expected) in examples {
      let token = try Token(issuer: issuer, account: account, secret: "JBSWY3DPEHPK3PXP")
      let original = token
      XCTAssertEqual(token.displayName, expected)
      XCTAssertEqual(token, original)
    }
  }

  func testRFC6238AllAlgorithms() throws {
    let times: [TimeInterval] = [59, 1_111_111_109, 1_111_111_111, 1_234_567_890, 2_000_000_000, 20_000_000_000]
    let expected = [
      ["94287082", "07081804", "14050471", "89005924", "69279037", "65353130"],
      ["46119246", "68084774", "67062674", "91819424", "90698825", "77737706"],
      ["90693936", "25091201", "99943326", "93441116", "38618901", "47863826"]
    ]
    let secrets = [
      "12345678901234567890",
      "12345678901234567890123456789012",
      "1234567890123456789012345678901234567890123456789012345678901234"
    ]
    for (index, algorithm) in OTPAlgorithm.allCases.enumerated() {
      let token = try Token(
        issuer: "RFC",
        account: "test",
        secret: Base32.encode(Data(secrets[index].utf8)),
        algorithm: algorithm,
        digits: 8)
      for (offset, time) in times.enumerated() {
        XCTAssertEqual(
          try TOTP.code(for: token, at: Date(timeIntervalSince1970: time)),
          expected[index][offset])
      }
    }
  }

  func testBase32() throws {
    for value in ["f", "fo", "foo", "foob", "fooba", "foobar"] {
      XCTAssertEqual(
        try Base32.decode(Base32.encode(Data(value.utf8))),
        Data(value.utf8))
    }
    XCTAssertEqual(try Base32.decode("MZXW6==="), Data("foo".utf8))
    for bad in ["A", "M1", "MZ", "MY=AAA", "====", "MY===", "MZXW6===="] {
      XCTAssertThrowsError(try Base32.decode(bad))
    }
  }

  func testURIAndTextRoundTrip() throws {
    let token = try Token(
      issuer: "公司: A & B",
      account: "a:b+tag@example.com /研发",
      secret: "JBSWY3DPEHPK3PXP",
      algorithm: .sha512,
      digits: 8,
      period: 60)
    XCTAssertTrue(try OTPURI.parse(OTPURI.encode(token)).sameIdentity(as: token))
    XCTAssertTrue(try BackupCodec.decode(BackupCodec.text([token]))[0].sameIdentity(as: token))
    let traditional = try OTPURI.parse("otpauth://totp/GitHub:alice?secret=JBSWY3DPEHPK3PXP&issuer=GitHub")
    XCTAssertEqual(traditional.issuer, "GitHub")
    XCTAssertEqual(traditional.account, "alice")
    for uri in [
      "otpauth://hotp/x?secret=MY&counter=1",
      "otpauth://totp/x?secret=MY&secret=MY",
      "otpauth://totp/a:x?secret=MY&issuer=b",
      "otpauth://totp/x?secret=MY&digits=9",
      "otpauth://totp/x?secret=MY&period=0"
    ] {
      XCTAssertThrowsError(try OTPURI.parse(uri))
    }
  }

  func testGoogleMigrationRoundTripAndTextImport() throws {
    let tokens = try (0 ..< 23).map { index in
      try Token(
        issuer: "Example \(index)",
        account: "用户+\(index)@example.com",
        secret: "JBSWY3DPEHPK3PXP",
        algorithm: index.isMultiple(of: 2) ? .sha1 : .sha256,
        digits: index.isMultiple(of: 3) ? 8 : 6)
    }
    let pages = try GoogleMigration.encode(tokens)
    XCTAssertGreaterThan(pages.count, 1)
    for page in pages {
      XCTAssertLessThanOrEqual(page.utf8.count, 2000)
      XCTAssertNoThrow(try QRCode.image(for: page))
    }
    let batches = try pages.map(GoogleMigration.parse)
    XCTAssertTrue(batches.enumerated().allSatisfy { offset, batch in
      batch.size == pages.count && batch.index == offset && batch.id == batches[0].id
    })
    let restored = batches.flatMap(\.tokens)
    XCTAssertEqual(restored.count, tokens.count)
    XCTAssertTrue(zip(tokens, restored).allSatisfy { $0.sameIdentity(as: $1) })
    let mixed = try BackupCodec.text([tokens[0]]) + Data((pages.joined(separator: "\n") + "\n").utf8)
    XCTAssertEqual(try BackupCodec.decode(mixed).count, tokens.count + 1)
  }

  func testGoogleMigrationRejectsUnsupportedAndMalformedData() throws {
    let token = try fixture()
    var nonstandard = token
    nonstandard.period = 60
    XCTAssertThrowsError(try GoogleMigration.encode([nonstandard]))
    let valid = try XCTUnwrap(GoogleMigration.encode([token]).first)
    XCTAssertThrowsError(try GoogleMigration.parse(valid + "&data=AA=="))
    XCTAssertThrowsError(try GoogleMigration.parse("otpauth-migration://offline?data=!!!"))

    // 公开测试密钥构造的最小 protobuf，type=1 表示 HOTP，不能作为 TOTP 导入。
    let hotp = Data([
      10,
      15,
      10,
      1,
      72,
      18,
      1,
      97,
      26,
      1,
      98,
      32,
      1,
      40,
      1,
      48,
      1,
      16,
      1,
      24,
      1,
      32,
      0,
      40,
      1
    ])
    let uri = "otpauth-migration://offline?data=" + hotp.base64EncodedString()
    XCTAssertThrowsError(try GoogleMigration.parse(uri))
    XCTAssertThrowsError(try BackupCodec.decode(Data(uri.utf8)))
    var totp = hotp
    totp[16] = 2
    let parsed = try GoogleMigration.parse("otpauth-migration://offline?data=" + totp.base64EncodedString())
    XCTAssertEqual(parsed.tokens[0].account, "a")
    XCTAssertEqual(parsed.tokens[0].issuer, "b")
    XCTAssertEqual(parsed.tokens[0].secret, "JA")
    totp[18] = 2
    totp.removeLast(2)
    let versionTwo = try GoogleMigration.parse("otpauth-migration://offline?data=" + totp.base64EncodedString())
    XCTAssertEqual(versionTwo.tokens.count, 1)
    XCTAssertEqual(versionTwo.size, 1)
    XCTAssertEqual(versionTwo.index, 0)
    XCTAssertEqual(versionTwo.id, 0)
  }

  func testEncryptedRoundTripAndAuthentication() throws {
    let token = try fixture()
    let firstBackup = try BackupCodec.encrypt([token], password: "正确的密码🔑123456")
    let secondBackup = try BackupCodec.encrypt([token], password: "正确的密码🔑123456")
    XCTAssertNotEqual(firstBackup, secondBackup)
    XCTAssertEqual(try BackupCodec.decode(firstBackup, password: "正确的密码🔑123456"), [token])
    XCTAssertThrowsError(try BackupCodec.decode(firstBackup, password: "wrong-password"))
    var tampered = firstBackup
    tampered[tampered.count / 2] ^= 1
    XCTAssertThrowsError(try BackupCodec.decode(tampered, password: "正确的密码🔑123456"))
    XCTAssertThrowsError(try BackupCodec.encrypt([token], password: "short"))
    XCTAssertThrowsError(try BackupCodec.decode(Data("TickKey/2\n{}".utf8), password: "1234567890"))
  }

  func testBrowserBackupWithEmptyAccountNames() throws {
    // 只使用公开测试密钥，真实用户备份不进入测试资源或日志。
    let text = """
    otpauth://totp/GitHub:?secret=JBSWY3DPEHPK3PXP&issuer=GitHub
    otpauth://totp/Example:alice?secret=JBSWY3DPEHPK3PXP&issuer=Example
    otpauth://totp/Prefix%3A%20Example:?secret=JBSWY3DPEHPK3PXP&issuer=Prefix%3A%20Example
    otpauth://totp/Issuer%20only:?secret=JBSWY3DPEHPK3PXP
    """
    let tokens = try BackupCodec.decode(Data(text.utf8))
    XCTAssertEqual(tokens.count, 4)
    XCTAssertEqual(tokens[0].issuer, "GitHub")
    XCTAssertEqual(tokens[0].account, "")
    XCTAssertEqual(tokens[1].account, "alice")
    XCTAssertEqual(tokens[2].issuer, "Prefix: Example")
    XCTAssertEqual(tokens[3].issuer, "Issuer only")
    let decoded = try BackupCodec.decode(BackupCodec.text(tokens))
    XCTAssertTrue(zip(tokens, decoded).allSatisfy { $0.sameIdentity(as: $1) })
    XCTAssertTrue(try OTPURI.encode(tokens[0]).hasPrefix("otpauth://totp/GitHub:?"))
    for token in tokens {
      XCTAssertEqual(try TOTP.code(for: token).count, 6)
    }

    let encrypted = try BackupCodec.encrypt(tokens, password: "browser-backup-password")
    XCTAssertEqual(try BackupCodec.decode(encrypted, password: "browser-backup-password"), tokens)
  }

  func testUnlabeledOrInvalidBrowserEntriesStillRejectEntireImport() throws {
    for uri in [
      "otpauth://totp/:?secret=MY",
      "otpauth://totp/?secret=MY&issuer=%20",
      "otpauth://totp/Example:?secret=INVALID1&issuer=Example",
      "otpauth://totp/Example:?secret=MY&issuer=Example&period=0"
    ] {
      let data = try BackupCodec.text([fixture()]) + Data(uri.utf8)
      XCTAssertThrowsError(try BackupCodec.decode(data))
    }
  }

  @MainActor
  func testIssuerOnlyAccountsPreserveIdentityAndPersistence() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let vault = try Vault(directory: root, testKey: Data(repeating: 5, count: 32))
    let model = try AppModel(vault: vault)
    let unnamed = try Token(issuer: "GitHub", account: "", secret: "JBSWY3DPEHPK3PXP")
    var named = unnamed
    named.account = "GitHub"
    let result = try model.add([unnamed, unnamed, named])
    XCTAssertEqual(result.added, 2)
    XCTAssertEqual(result.duplicates, 1)
    XCTAssertEqual(try vault.load().map(\.account), ["", "GitHub"])
    var edited = model.tokens[0]
    edited.period = 60
    try model.update(edited)
    XCTAssertEqual(try vault.load()[0].account, "")
    XCTAssertEqual(try vault.load()[0].period, 60)
  }

  func testBackupFromIndependentPythonImplementation() throws {
    let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "v1-backup", withExtension: "txt"))
    let tokens = try BackupCodec.decode(Data(contentsOf: url), password: "interop-password-2026")
    XCTAssertEqual(tokens.count, 1)
    XCTAssertEqual(tokens[0].account, "interop@example.com")
    XCTAssertEqual(try TOTP.code(for: tokens[0], at: Date(timeIntervalSince1970: 59)), "94287082")
  }

  func testMalformedImportDoesNotSilentlySkipLines() throws {
    let data = try BackupCodec.text([fixture()]) + Data("not-an-account\n".utf8)
    XCTAssertThrowsError(try BackupCodec.decode(data))
  }

  func testIdentityIncludesEveryEnteredField() throws {
    let token = try fixture()
    var changed = token
    changed.id = UUID()
    XCTAssertTrue(token.sameIdentity(as: changed))
    changed.account += " "
    XCTAssertFalse(token.sameIdentity(as: changed))
    changed = token
    changed.issuer = "other"
    XCTAssertFalse(token.sameIdentity(as: changed))
    changed = token
    changed.secret = "MY"
    XCTAssertFalse(token.sameIdentity(as: changed))
    changed = token
    changed.period = 60
    XCTAssertFalse(token.sameIdentity(as: changed))
    changed = token
    changed.digits = 8
    XCTAssertFalse(token.sameIdentity(as: changed))
    changed = token
    changed.algorithm = .sha256
    XCTAssertFalse(token.sameIdentity(as: changed))
  }

  func testEncryptedStorageReloadAndWrongKey() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let key = Data(repeating: 42, count: 32)
    let token = try fixture()
    let vault = try Vault(directory: root, testKey: key)
    try vault.save([token])
    let reopened = try Vault(directory: root, testKey: key)
    XCTAssertEqual(try reopened.load(), [token])
    XCTAssertThrowsError(try Vault(directory: root, testKey: Data(repeating: 0, count: 32)).load())
    let raw = try Data(contentsOf: root.appendingPathComponent("vault.sqlite"))
    XCTAssertNil(raw.range(of: Data(token.secret.utf8)))
    XCTAssertNil(raw.range(of: Data(token.account.utf8)))
    try vault.save([])
    XCTAssertTrue(try vault.load().isEmpty)
  }

  func testCountdownBoundary() throws {
    let token = try fixture()
    XCTAssertEqual(TOTP.remainingFraction(for: token, at: Date(timeIntervalSince1970: 60)), 1)
    XCTAssertEqual(
      TOTP.remainingFraction(for: token, at: Date(timeIntervalSince1970: 59.9)),
      0.1 / 30,
      accuracy: 0.0001)
  }

  @MainActor
  func testImportDeduplicationAndEditingPersistAtomically() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let vault = try Vault(directory: root, testKey: Data(repeating: 1, count: 32))
    let model = try AppModel(vault: vault)
    let first = try fixture()
    var other = first
    other.secret = "MY"
    let result = try model.add([first, first, other])
    XCTAssertEqual(result.added, 2)
    XCTAssertEqual(result.duplicates, 1)
    XCTAssertEqual(Set(model.tokens.map(\.id)).count, 2)
    XCTAssertEqual(try model.add([first, other]).duplicates, 2)
    var edited = model.tokens[1]
    edited.secret = first.secret
    XCTAssertThrowsError(try model.update(edited))
    XCTAssertEqual(try vault.load(), model.tokens)
  }

  private func fixture() throws -> Token {
    try Token(
      issuer: "GitHub",
      account: "alice@example.com",
      secret: "JBSWY3DPEHPK3PXP")
  }

  /// 后台导入期间旧状态可读、交错写入被拒绝，成功后内存和磁盘一次性保持一致。
  @MainActor
  func testBackgroundImportPreservesAtomicityAndDeduplication() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let vault = try Vault(directory: root, testKey: Data(repeating: 3, count: 32))
    let model = try AppModel(vault: vault)
    let first = try fixture()
    _ = try model.add([first])
    let original = model.tokens
    let imported = try (0 ..< 500).map {
      try Token(issuer: "Example", account: "account-\($0)", secret: "JBSWY3DPEHPK3PXP")
    }
    let result: Result<String, Error> = await withCheckedContinuation { continuation in
      model.importTokens(imported + imported + [first]) { continuation.resume(returning: $0) }
      XCTAssertEqual(model.tokens, original)
      do {
        try model.delete(original[0])
        XCTFail("导入期间不应允许交错写入")
      } catch {
        // 导入占用期间应返回「正在导入」，而不是误报保险库损坏。
        if case TickKeyError.busy = error {} else {
          XCTFail("导入期间的写入应返回 busy 错误：\(error)")
        }
        XCTAssertEqual(model.tokens, original)
      }
    }
    _ = try result.get()
    XCTAssertEqual(model.tokens.count, 501)
    XCTAssertEqual(model.tokens.first, original.first)
    XCTAssertEqual(Set(model.tokens.map(\.id)).count, 501)
    XCTAssertEqual(try vault.load(), model.tokens)
    try model.delete(model.tokens[0])
    XCTAssertEqual(model.tokens.count, 500)
  }

  /// 失败不发布半批数据，且解除写入保护，使下一次正常导入仍可完成。
  @MainActor
  func testBackgroundImportFailureLeavesVaultIntactAndAllowsRetry() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let vault = try Vault(directory: root, testKey: Data(repeating: 4, count: 32))
    let model = try AppModel(vault: vault)
    let valid = try fixture()
    var invalid = valid
    invalid.secret = "invalid!"
    let failed: Result<String, Error> = await withCheckedContinuation { continuation in
      model.importTokens([valid, invalid]) { continuation.resume(returning: $0) }
    }
    XCTAssertThrowsError(try failed.get())
    XCTAssertTrue(model.tokens.isEmpty)
    XCTAssertTrue(try vault.load().isEmpty)
    let retry: Result<String, Error> = await withCheckedContinuation { continuation in
      model.importTokens([valid]) { continuation.resume(returning: $0) }
    }
    _ = try retry.get()
    XCTAssertEqual(model.tokens.count, 1)
    XCTAssertEqual(try vault.load(), model.tokens)
  }
}

/// 批量删除覆盖阈值、搜索范围以及整批持久化，不接触真实账户。
extension CoreTests {
  func testSelectionScopeAndDeletionConfirmationThreshold() throws {
    let tokens = try (1 ... 7).map {
      try Token(issuer: "Test", account: "account-\($0)", secret: "JBSWY3DPEHPK3PXP")
    }
    var selection = AccountSelection()
    XCTAssertNil(selection.deletion(in: tokens))
    selection.selectAll(in: Array(tokens.prefix(5)))
    XCTAssertFalse(try XCTUnwrap(selection.deletion(in: tokens)).requiresSecondConfirmation)
    selection.toggle(tokens[5].id)
    XCTAssertTrue(try XCTUnwrap(selection.deletion(in: tokens)).requiresSecondConfirmation)
    selection.invert(in: tokens)
    XCTAssertEqual(selection.ids, [tokens[6].id])
    XCTAssertFalse(try XCTUnwrap(selection.deletion(in: tokens)).requiresSecondConfirmation)
    // 搜索结果只有一项时，全选也必须二次确认。
    XCTAssertTrue(try XCTUnwrap(selection.deletion(in: [tokens[6]])).requiresSecondConfirmation)
    selection.selectAll(in: tokens)
    let request = try XCTUnwrap(selection.deletion(in: tokens))
    XCTAssertTrue(request.requiresSecondConfirmation)
    selection.invert(in: tokens)
    XCTAssertNil(selection.deletion(in: tokens))
    XCTAssertEqual(request.ids.count, 7)
    selection.selectAll(in: tokens)
    selection.retainVisible(Array(tokens.prefix(2)))
    XCTAssertEqual(selection.ids, Set(tokens.prefix(2).map(\.id)))
    selection.retainVisible([])
    XCTAssertTrue(selection.ids.isEmpty)
  }

  @MainActor
  func testBatchDeletionPersistsOnlySelectedIDs() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let vault = try Vault(directory: root, testKey: Data(repeating: 8, count: 32))
    let model = try AppModel(vault: vault)
    let tokens = try (1 ... 7).map {
      try Token(issuer: "Test", account: "account-\($0)", secret: "JBSWY3DPEHPK3PXP")
    }
    _ = try model.add(tokens)
    let before = model.tokens
    try model.delete(ids: [])
    XCTAssertEqual(model.tokens, before)
    let deleted = Set(before.prefix(6).map(\.id))
    try model.delete(ids: deleted.union([UUID()]))
    XCTAssertEqual(model.tokens, [before[6]])
    XCTAssertEqual(try vault.load(), model.tokens)
    try model.delete(ids: [before[6].id])
    XCTAssertTrue(model.tokens.isEmpty)
    XCTAssertTrue(try vault.load().isEmpty)
  }

  #if os(macOS)
    /// 显式深浅色不依赖系统当前外观，视图与卡片颜色应随外观立即重算。
    @MainActor
    func testMacBackgroundColorsFollowEffectiveAppearance() throws {
      let background = MacAppearanceBackgroundView(color: .windowBackgroundColor)
      let card = try MacTokenCard(token: fixture())
      for name in [NSAppearance.Name.darkAqua, .aqua, .darkAqua, .aqua] {
        let appearance = try XCTUnwrap(NSAppearance(named: name))
        background.appearance = appearance
        background.updateLayer()
        card.appearance = appearance
        card.tick(hidden: false)
        appearance.performAsCurrentDrawingAppearance {
          XCTAssertEqual(background.layer?.backgroundColor, NSColor.windowBackgroundColor.cgColor)
          XCTAssertEqual(card.layer?.backgroundColor, NSColor.controlBackgroundColor.cgColor)
        }
      }
    }
  #endif
}

/// 覆盖 otpauth 兼容性、迁移链接容错、偏好持久化与按内容识别的导入入口。
extension CoreTests {
  /// Key URI 规范允许「发行方:」后带空格；导出时同时写入标签前缀和 issuer 参数。
  func testURIAcceptsSpaceAfterIssuerSeparatorAndExportsIssuerPrefix() throws {
    let parsed = try OTPURI.parse(
      "otpauth://totp/Example:%20%20alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Example")
    XCTAssertEqual(parsed.issuer, "Example")
    XCTAssertEqual(parsed.account, "alice@example.com")
    let encoded = try OTPURI.encode(parsed)
    XCTAssertTrue(encoded.hasPrefix("otpauth://totp/Example:alice@example.com?"))
    XCTAssertTrue(encoded.contains("issuer=Example"))
    let noIssuer = try Token(issuer: "", account: "bob", secret: "JBSWY3DPEHPK3PXP")
    XCTAssertFalse(try OTPURI.encode(noIssuer).contains("issuer="))
    XCTAssertTrue(try OTPURI.parse(OTPURI.encode(noIssuer)).sameIdentity(as: noIssuer))
  }

  /// 保留字符必须编码；以空格开头的账户名不加前缀，往返后身份保持一致。
  func testURIEncodingEscapesReservedCharactersAndPreservesIdentity() throws {
    let reserved = try Token(issuer: "A+B&C=D", account: "x+y@example.com", secret: "JBSWY3DPEHPK3PXP")
    let encoded = try OTPURI.encode(reserved)
    XCTAssertTrue(encoded.contains("issuer=A%2BB%26C%3DD"))
    XCTAssertTrue(try OTPURI.parse(encoded).sameIdentity(as: reserved))
    let spaced = try Token(issuer: "Example", account: " leading", secret: "JBSWY3DPEHPK3PXP")
    XCTAssertTrue(try OTPURI.parse(OTPURI.encode(spaced)).sameIdentity(as: spaced))
    XCTAssertThrowsError(try OTPURI.parse("otpauth://totp/Example:alice?secret=JBSWY3DPEHPK3PXP&issuer=Other"))
  }

  /// 第三方工具可能输出 URL 安全或无填充的 Base64，内容相同时应得到相同账户。
  func testGoogleMigrationAcceptsURLSafeAndUnpaddedBase64() throws {
    let token = try Token(issuer: "Example", account: "alice", secret: "JBSWY3DPEHPK3PXP")
    let uri = try XCTUnwrap(GoogleMigration.encode([token]).first)
    let items = try XCTUnwrap(URLComponents(string: uri)?.queryItems)
    let standard = try XCTUnwrap(items.first?.value)
    let variant = standard
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
    let parsed = try GoogleMigration.parse("otpauth-migration://offline?data=" + variant)
    XCTAssertTrue(try XCTUnwrap(parsed.tokens.first).sameIdentity(as: token))
    XCTAssertThrowsError(try GoogleMigration.parse("otpauth-migration://offline?data=A"))
  }

  /// 名称展示：副标题去掉重复前缀，组合名称与原有规则一致。
  func testDetailRemovesIssuerPrefixOnlyForDisplay() throws {
    let token = try Token(issuer: "GitHub", account: "GitHub: alice", secret: "JBSWY3DPEHPK3PXP")
    XCTAssertEqual(token.detail, "alice")
    XCTAssertEqual(token.displayName, "GitHub · alice")
    XCTAssertEqual(token.account, "GitHub: alice")
    let accountOnly = try Token(issuer: "", account: "bob", secret: "JBSWY3DPEHPK3PXP")
    XCTAssertEqual(accountOnly.detail, "bob")
    XCTAssertEqual(accountOnly.displayName, "bob")
  }

  /// 密钥录入允许小写和分组空格；验证码展示只在中间分组。
  func testSecretNormalizationAndCodeGrouping() throws {
    let token = try Token(issuer: "Example", account: "alice", secret: "jbsw y3dp ehpk 3pxp")
    XCTAssertEqual(token.secret, "JBSWY3DPEHPK3PXP")
    XCTAssertEqual(TOTP.display("123456"), "123 456")
    XCTAssertEqual(TOTP.display("1234567"), "123 4567")
    XCTAssertEqual(TOTP.display("12345678"), "1234 5678")
    XCTAssertThrowsError(try Token(issuer: "Example", account: "alice", secret: "JBSWY3DPEHPK3PX1"))
    XCTAssertThrowsError(try Token(issuer: "Example", account: "a\nb", secret: "JBSWY3DPEHPK3PXP"))
  }

  /// 偏好包含解锁开关；非法语言和外观值回退到跟随系统。
  func testPreferencesPersistUnlockAndRejectInvalidValues() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let vault = try Vault(directory: root, testKey: Data(repeating: 9, count: 32))
    XCTAssertEqual(try vault.preferences(), Preferences())
    try vault.savePreferences(Preferences(language: "zh-Hant", appearance: 2, requiresUnlock: true))
    let reopened = try Vault(directory: root, testKey: Data(repeating: 9, count: 32))
    XCTAssertEqual(try reopened.preferences(), Preferences(language: "zh-Hant", appearance: 2, requiresUnlock: true))
    try reopened.savePreferences(Preferences(language: "fr", appearance: 7, requiresUnlock: false))
    XCTAssertEqual(try reopened.preferences(), Preferences())
  }

  /// 文件导入按内容区分加密备份、二维码图片和文本，不依赖扩展名。
  func testImportDecoderRecognizesFilesByContent() throws {
    let token = try fixture()
    let image = try pngData(QRCode.image(for: token))
    XCTAssertTrue(ImportDecoder.isImage(image))
    XCTAssertFalse(try ImportDecoder.isImage(BackupCodec.text([token])))
    XCTAssertTrue(try XCTUnwrap(ImportDecoder.decodeFile(image).tokens.first).sameIdentity(as: token))
    let text = try ImportDecoder.decodeFile(BackupCodec.text([token]))
    XCTAssertTrue(try XCTUnwrap(text.tokens.first).sameIdentity(as: token))
    let encrypted = try BackupCodec.encrypt([token], password: "import-decoder-2026")
    XCTAssertEqual(try ImportDecoder.decodeFile(encrypted, password: "import-decoder-2026").tokens, [token])
    XCTAssertThrowsError(try ImportDecoder.decodeFile(encrypted))
    XCTAssertThrowsError(try ImportDecoder.decodeFile(Data()))

    // 不含二维码的图片应明确报告未找到账户，而不是静默导入 0 个。
    let blank = try pngData(blankImage())
    XCTAssertThrowsError(try ImportDecoder.decodeFile(blank)) { error in
      if case TickKeyError.noAccountsFound = error {} else {
        XCTFail("空白图片应返回 noAccountsFound：\(error)")
      }
    }
  }

  /// 剪贴板优先识别 otpauth 文本，其次识别截图；都没有时返回明确错误。
  func testPasteboardImportPrefersTextThenImage() throws {
    let token = try fixture()
    let text = try OTPURI.encode(token)
    XCTAssertEqual(try ImportDecoder.decodePasteboard(text: text, image: nil).tokens.count, 1)
    let image = try pngData(QRCode.image(for: token))
    XCTAssertEqual(try ImportDecoder.decodePasteboard(text: "hello", image: image).tokens.count, 1)
    XCTAssertThrowsError(try ImportDecoder.decodePasteboard(text: "hello", image: nil))
    XCTAssertThrowsError(try ImportDecoder.decodePasteboard(text: "otpauth://totp/x?secret=1", image: image))
  }

  /// 导出文件名包含日期，便于区分多次备份。
  func testBackupFileNameContainsDate() {
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let name = BackupCodec.fileName(extension: "tickkey", date: date)
    XCTAssertTrue(name.hasPrefix("TickKey-backup-20"))
    XCTAssertTrue(name.hasSuffix(".tickkey"))
    XCTAssertEqual(name.count, "TickKey-backup-yyyyMMdd-HHmm.tickkey".count)
  }

  /// 纯白位图，用于验证没有二维码的图片。
  private func blankImage() throws -> CGImage {
    let context = try XCTUnwrap(CGContext(
      data: nil,
      width: 64,
      height: 64,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
    return try XCTUnwrap(context.makeImage())
  }

  /// 使用 ImageIO 生成 PNG，两端测试共用，不依赖 UIKit 或 AppKit 绘图。
  private func pngData(_ image: CGImage) throws -> Data {
    let data = NSMutableData()
    let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    return data as Data
  }
}

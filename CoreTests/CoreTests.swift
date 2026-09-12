import XCTest
#if os(macOS)
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

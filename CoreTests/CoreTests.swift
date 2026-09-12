import XCTest
#if os(macOS)
@testable import TickKeyMac
#else
@testable import TickKey
#endif

final class CoreTests: XCTestCase {
    func testRFC6238AllAlgorithms() throws {
        let times: [TimeInterval] = [59, 1111111109, 1111111111, 1234567890, 2000000000, 20000000000]
        let expected = [
            ["94287082", "07081804", "14050471", "89005924", "69279037", "65353130"],
            ["46119246", "68084774", "67062674", "91819424", "90698825", "77737706"],
            ["90693936", "25091201", "99943326", "93441116", "38618901", "47863826"]]
        let secrets = ["12345678901234567890", "12345678901234567890123456789012", "1234567890123456789012345678901234567890123456789012345678901234"]
        for (index, algorithm) in OTPAlgorithm.allCases.enumerated() {
            let token = try Token(issuer: "RFC", account: "test", secret: Base32.encode(Data(secrets[index].utf8)), algorithm: algorithm, digits: 8)
            for (offset, time) in times.enumerated() { XCTAssertEqual(try TOTP.code(for: token, at: Date(timeIntervalSince1970: time)), expected[index][offset]) }
        }
    }
    func testBase32() throws {
        for value in ["f", "fo", "foo", "foob", "fooba", "foobar"] { XCTAssertEqual(try Base32.decode(Base32.encode(Data(value.utf8))), Data(value.utf8)) }
        XCTAssertEqual(try Base32.decode("MZXW6==="), Data("foo".utf8))
        for bad in ["A", "M1", "MZ", "MY=AAA", "====", "MY===", "MZXW6===="] { XCTAssertThrowsError(try Base32.decode(bad)) }
    }
    func testURIAndTextRoundTrip() throws {
        let token = try Token(issuer: "公司: A & B", account: "a:b+tag@example.com /研发", secret: "JBSWY3DPEHPK3PXP", algorithm: .sha512, digits: 8, period: 60)
        XCTAssertTrue(try OTPURI.parse(OTPURI.encode(token)).sameIdentity(as: token))
        XCTAssertTrue(try BackupCodec.decode(BackupCodec.text([token]))[0].sameIdentity(as: token))
        let traditional = try OTPURI.parse("otpauth://totp/GitHub:alice?secret=JBSWY3DPEHPK3PXP&issuer=GitHub")
        XCTAssertEqual(traditional.issuer, "GitHub"); XCTAssertEqual(traditional.account, "alice")
        for uri in ["otpauth://hotp/x?secret=MY&counter=1", "otpauth://totp/x?secret=MY&secret=MY", "otpauth://totp/a:x?secret=MY&issuer=b", "otpauth://totp/x?secret=MY&digits=9", "otpauth://totp/x?secret=MY&period=0"] { XCTAssertThrowsError(try OTPURI.parse(uri)) }
    }
    func testEncryptedRoundTripAndAuthentication() throws {
        let token = try fixture()
        let a = try BackupCodec.encrypt([token], password: "正确的密码🔑123456")
        let b = try BackupCodec.encrypt([token], password: "正确的密码🔑123456")
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(try BackupCodec.decode(a, password: "正确的密码🔑123456"), [token])
        XCTAssertThrowsError(try BackupCodec.decode(a, password: "wrong-password"))
        var tampered = a; tampered[tampered.count / 2] ^= 1
        XCTAssertThrowsError(try BackupCodec.decode(tampered, password: "正确的密码🔑123456"))
        XCTAssertThrowsError(try BackupCodec.encrypt([token], password: "short"))
        XCTAssertThrowsError(try BackupCodec.decode(Data("TickKey/2\n{}".utf8), password: "1234567890"))
    }
    func testBackupFromIndependentPythonImplementation() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "v1-backup", withExtension: "txt"))
        let tokens = try BackupCodec.decode(Data(contentsOf: url), password: "interop-password-2026")
        XCTAssertEqual(tokens.count, 1)
        XCTAssertEqual(tokens[0].account, "interop@example.com")
        XCTAssertEqual(try TOTP.code(for: tokens[0], at: Date(timeIntervalSince1970: 59)), "94287082")
    }
    func testMalformedImportDoesNotSilentlySkipLines() throws {
        let data = BackupCodec.text([try fixture()]) + Data("not-an-account\n".utf8)
        XCTAssertThrowsError(try BackupCodec.decode(data))
    }
    func testIdentityIncludesEveryEnteredField() throws {
        let token = try fixture()
        var changed = token; changed.id = UUID(); XCTAssertTrue(token.sameIdentity(as: changed))
        changed.account += " "; XCTAssertFalse(token.sameIdentity(as: changed))
        changed = token; changed.issuer = "other"; XCTAssertFalse(token.sameIdentity(as: changed))
        changed = token; changed.secret = "MY"; XCTAssertFalse(token.sameIdentity(as: changed))
        changed = token; changed.period = 60; XCTAssertFalse(token.sameIdentity(as: changed))
        changed = token; changed.digits = 8; XCTAssertFalse(token.sameIdentity(as: changed))
        changed = token; changed.algorithm = .sha256; XCTAssertFalse(token.sameIdentity(as: changed))
    }
    func testEncryptedStorageReloadAndWrongKey() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let key = Data(repeating: 42, count: 32), token = try fixture()
        let vault = try Vault(directory: root, testKey: key)
        try vault.save([token])
        let reopened = try Vault(directory: root, testKey: key)
        XCTAssertEqual(try reopened.load(), [token])
        XCTAssertThrowsError(try Vault(directory: root, testKey: Data(repeating: 0, count: 32)).load())
        let raw = try Data(contentsOf: root.appendingPathComponent("vault.sqlite"))
        XCTAssertNil(raw.range(of: Data(token.secret.utf8)))
        XCTAssertNil(raw.range(of: Data(token.account.utf8)))
        try vault.save([]); XCTAssertTrue(try vault.load().isEmpty)
    }
    func testCountdownBoundary() throws {
        let token = try fixture()
        XCTAssertEqual(TOTP.remainingFraction(for: token, at: Date(timeIntervalSince1970: 60)), 1)
        XCTAssertEqual(TOTP.remainingFraction(for: token, at: Date(timeIntervalSince1970: 59.9)), 0.1 / 30, accuracy: 0.0001)
    }
    @MainActor
    func testImportDeduplicationAndEditingPersistAtomically() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let vault = try Vault(directory: root, testKey: Data(repeating: 1, count: 32))
        let model = try AppModel(vault: vault)
        let first = try fixture()
        var other = first; other.secret = "MY"
        let result = try model.add([first, first, other])
        XCTAssertEqual(result.added, 2); XCTAssertEqual(result.duplicates, 1)
        XCTAssertEqual(Set(model.tokens.map(\.id)).count, 2)
        XCTAssertEqual(try model.add([first, other]).duplicates, 2)
        var edited = model.tokens[1]; edited.secret = first.secret
        XCTAssertThrowsError(try model.update(edited))
        XCTAssertEqual(try vault.load(), model.tokens)
    }
    private func fixture() throws -> Token { try Token(issuer: "GitHub", account: "alice@example.com", secret: "JBSWY3DPEHPK3PXP") }
}

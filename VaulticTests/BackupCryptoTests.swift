import XCTest
@testable import Vaultic

/// `BackupCrypto` is the only thing standing between a `.autheris` file and the
/// plaintext of every TOTP secret a user owns, so these cases pin both the happy
/// path and the ways a wrong key or a tampered file has to fail closed.
///
/// `@MainActor` because the app target is built with
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which makes `BackupCrypto`
/// main-actor isolated there. Annotating the class keeps the test valid whether
/// or not the test target inherits that setting.
@MainActor
final class BackupCryptoTests: XCTestCase {

    private let password = "correct horse battery staple"

    private let plaintext = Data("""
    [{"label":"GitHub","account":"octocat","secret":"JBSWY3DPEHPK3PXP"}]
    """.utf8)

    // MARK: - Helpers

    private func encrypt(password: String? = nil) throws -> Data {
        try BackupCrypto.encrypt(plaintext: plaintext, password: password ?? self.password)
    }

    private func decrypt(_ data: Data, password: String? = nil) throws -> Data {
        try BackupCrypto.decrypt(data: data, password: password ?? self.password)
    }

    /// Re-encodes the envelope with one field replaced, to forge a tampered file.
    private func envelopeReplacing(_ key: String, with value: Any, in encrypted: Data) throws -> Data {
        var envelope = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encrypted) as? [String: Any]
        )
        envelope[key] = value
        return try JSONSerialization.data(withJSONObject: envelope)
    }

    // MARK: - Happy path

    func testRoundTripReturnsTheOriginalPlaintext() throws {
        let encrypted = try encrypt()

        XCTAssertEqual(try decrypt(encrypted), plaintext)
    }

    func testAnAccentedPasswordOpensHoweverItsAccentsWereTyped() throws {
        // "é" as one code point, and as "e" plus a combining accent: the same
        // password to the person typing it, different bytes to PBKDF2.
        let composed = "caf\u{00E9} au lait 2026"
        let decomposed = "cafe\u{0301} au lait 2026"
        XCTAssertNotEqual(Array(composed.utf8), Array(decomposed.utf8))

        let sealed = try encrypt(password: decomposed)

        XCTAssertEqual(try decrypt(sealed, password: composed), plaintext)
        XCTAssertEqual(try decrypt(sealed, password: decomposed), plaintext)
    }

    func testEncryptedFileContainsNoPlaintext() throws {
        let encrypted = try encrypt()

        XCTAssertNil(encrypted.range(of: plaintext))
        XCTAssertNil(encrypted.range(of: Data("JBSWY3DPEHPK3PXP".utf8)),
                     "the TOTP secret must not survive as readable bytes")
    }

    func testEachEncryptionUsesAFreshSaltAndNonce() throws {
        // Same password and same plaintext must not produce the same file twice:
        // an identical output would leak that two backups are byte-identical.
        XCTAssertNotEqual(try encrypt(), try encrypt())
    }

    // MARK: - Failing closed

    func testWrongPasswordFailsAuthenticationRatherThanReturningGarbage() throws {
        let encrypted = try encrypt()

        XCTAssertThrowsError(try decrypt(encrypted, password: "wrong password")) { error in
            XCTAssertFalse(error is BackupCrypto.BackupCryptoError,
                           "a wrong password is an authentication failure, not a malformed envelope")
        }
    }

    func testTamperedCiphertextIsRejected() throws {
        let encrypted = try encrypt()
        var combined = try XCTUnwrap(
            Data(base64Encoded: try XCTUnwrap(
                (try JSONSerialization.jsonObject(with: encrypted) as? [String: Any])?["combined"] as? String
            ))
        )
        combined[combined.count - 1] ^= 0xFF

        let tampered = try envelopeReplacing("combined", with: combined.base64EncodedString(),
                                             in: encrypted)

        XCTAssertThrowsError(try decrypt(tampered))
    }

    func testTamperedSaltIsRejected() throws {
        // The salt drives key derivation, so a swapped salt must not decrypt —
        // under a fresh key the GCM tag cannot validate.
        let tampered = try envelopeReplacing(
            "salt",
            with: Data(repeating: 0xAB, count: 16).base64EncodedString(),
            in: try encrypt()
        )

        XCTAssertThrowsError(try decrypt(tampered))
    }

    func testUnsupportedVersionIsRejected() throws {
        let data = try envelopeReplacing("version", with: 99, in: try encrypt())

        XCTAssertThrowsError(try decrypt(data)) { error in
            guard let cryptoError = error as? BackupCrypto.BackupCryptoError else {
                return XCTFail("expected BackupCryptoError, got \(error)")
            }
            guard case .unsupportedVersion = cryptoError else {
                return XCTFail("expected .unsupportedVersion, got \(cryptoError)")
            }
        }
    }

    func testNonJSONInputIsRejectedAsAnInvalidEnvelope() throws {
        XCTAssertThrowsError(try decrypt(Data("definitely not a backup".utf8))) { error in
            guard let cryptoError = error as? BackupCrypto.BackupCryptoError else {
                return XCTFail("expected BackupCryptoError, got \(error)")
            }
            guard case .invalidEnvelope = cryptoError else {
                return XCTFail("expected .invalidEnvelope, got \(cryptoError)")
            }
        }
    }

    func testEmptyInputIsRejected() throws {
        XCTAssertThrowsError(try decrypt(Data()))
    }

    // MARK: - Format versions

    func testNewBackupsRecordTheirIterationCount() throws {
        let envelope = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try encrypt()) as? [String: Any]
        )

        XCTAssertEqual(envelope["version"] as? Int, 2)
        XCTAssertEqual(envelope["iterations"] as? Int, BackupCrypto.currentIterations)
    }

    /// Written by the version 1 code (120,000 iterations, hand-rolled PBKDF2)
    /// before this format change, so it proves old backups still open.
    func testAVersionOneBackupStillDecrypts() throws {
        let v1 = try XCTUnwrap(Data(base64Encoded: "eyJzYWx0IjoiTnBUdXo5dkFmell4Q1kzMVI5ZGtXQT09IiwiY29tYmluZWQiOiJNaHY5eVh2WjdNbldJdVwvSDNoeHFRUlk2MHlVT3h3TVpcL3hnOEFueHB5YlwvTkE0cDl3VnpScG5UQ3pIRFJESjJ4QVIxbDliTE92TFwvUlJGdjVVem1QWW9XazJPU0R1MkxRRVM1XC96K1M1YzZ0REJKTWxcL1NENURXV3hJcnMxK3BEcSIsInZlcnNpb24iOjF9"))

        XCTAssertEqual(try decrypt(v1), plaintext)
    }

    func testAnIterationCountOutsideTheAcceptedRangeIsRejected() throws {
        for count in [1, 50_000_000] {
            let forged = try envelopeReplacing("iterations", with: count, in: try encrypt())

            XCTAssertThrowsError(try decrypt(forged)) { error in
                guard case .invalidEnvelope? = error as? BackupCrypto.BackupCryptoError else {
                    return XCTFail("expected .invalidEnvelope for \(count), got \(error)")
                }
            }
        }
    }

    func testAVersionTwoBackupWithoutAnIterationCountIsRejected() throws {
        var envelope = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try encrypt()) as? [String: Any]
        )
        envelope.removeValue(forKey: "iterations")
        let data = try JSONSerialization.data(withJSONObject: envelope)

        XCTAssertThrowsError(try decrypt(data))
    }
}

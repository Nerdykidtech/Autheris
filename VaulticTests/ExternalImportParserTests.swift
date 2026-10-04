import XCTest
@testable import Vaultic

/// Importing a backup from another authenticator.
///
/// The cases that matter here are the ones where the entry is *dropped* or *downgraded*
/// rather than refused: this parser used to skip every `hotp` entry outright, so a
/// user moving from Aegis or andOTP lost those accounts with nothing on screen to say
/// so. A counter read from the wrong place is worse than a skip — it imports as 0 and
/// produces codes the service rejects — which is why the counter's location is pinned
/// here for each format.
///
/// The secrets are Base32 and at least 16 characters because `OTPGenerator.isValidSecret`
/// is the parser's guard, so a shorter fixture would be skipped for the wrong reason and
/// the test would pass without testing anything.
// The app target defaults to main-actor isolation, which makes the types under
// test main-actor isolated too.
@MainActor
final class ExternalImportParserTests: XCTestCase {

    private let secret = "JBSWY3DPEHPK3PXP"

    private func parse(_ json: String) throws -> [OTPCode] {
        try ExternalImportParser.parse(data: Data(json.utf8))
    }

    // MARK: - Aegis

    private func aegisEntry(type: String,
                            counterField: String?,
                            counterInsideInfo: Bool = false) -> String {
        let counter = counterField.map { #", "counter": \#($0)"# } ?? ""
        let infoCounter = counterInsideInfo ? counter : ""
        let infoPlain = """
        "secret": "\(secret)", "algo": "SHA1", "digits": 6, "period": 30\(infoCounter)
        """
        return """
        {
          "version": 1,
          "header": {},
          "db": {
            "version": 2,
            "entries": [
              {
                "type": "\(type)",
                "name": "alice@example.com",
                "issuer": "Example"\(counterInsideInfo ? "" : counter),
                "info": { \(infoPlain) }
              }
            ]
          }
        }
        """
    }

    func testAnAegisHotpEntryIsImportedWithItsCounter() throws {
        let tokens = try parse(aegisEntry(type: "hotp", counterField: "4"))

        XCTAssertEqual(tokens.count, 1)
        XCTAssertEqual(tokens.first?.kind, .hotp)
        XCTAssertEqual(tokens.first?.counter, 4)
        XCTAssertEqual(tokens.first?.label, "Example")
    }

    func testAnAegisHotpCounterIsFoundInsideInfoToo() throws {
        // The export has carried the counter beside the type *and* inside `info`
        // depending on version, and reading the wrong one yields 0 rather than an
        // error. Both shapes have to work.
        let tokens = try parse(aegisEntry(type: "hotp", counterField: "7", counterInsideInfo: true))

        XCTAssertEqual(tokens.first?.kind, .hotp)
        XCTAssertEqual(tokens.first?.counter, 7)
    }

    func testAnAegisHotpEntryWithNoCounterStartsAtZero() throws {
        let tokens = try parse(aegisEntry(type: "hotp", counterField: nil))

        XCTAssertEqual(tokens.first?.kind, .hotp)
        XCTAssertEqual(tokens.first?.counter, 0)
    }

    func testAnAegisTotpEntryIgnoresACounter() throws {
        // A time-based entry that happens to carry a `counter` must not read as
        // counter-based: the kind is what decides, and `period` not `counter` is what
        // it uses.
        let tokens = try parse(aegisEntry(type: "totp", counterField: "4"))

        XCTAssertEqual(tokens.first?.kind, .totp)
        XCTAssertEqual(tokens.first?.counter, 0)
        XCTAssertEqual(tokens.first?.period, 30)
    }

    func testAnAegisSteamEntryIsStillSkipped() throws {
        // Steam Guard is its own algorithm, not either of the two the app can
        // generate, so it is refused rather than imported as something that produces
        // codes the service will reject.
        XCTAssertEqual(try parse(aegisEntry(type: "steam", counterField: nil)).count, 0)
    }

    func testAnEncryptedAegisVaultIsRefusedRatherThanImportedEmpty() throws {
        let json = """
        { "header": { "slots": [{}] }, "db": { "entries": [] } }
        """

        XCTAssertThrowsError(try parse(json)) { error in
            XCTAssertEqual(error as? ExternalImportError, .encryptedAegisVault)
        }
    }

    func testARealPlainAegisExportWithNullSlotsAndParamsIsImported() throws {
        // This is the header Aegis really writes for an unencrypted export, not `{}`.
        // Reading any non-empty header as encrypted refused every plain export, so the
        // import advertised in Settings never worked against a file from Aegis itself.
        let json = """
        {
          "version": 1,
          "header": { "slots": null, "params": null },
          "db": {
            "version": 2,
            "entries": [
              {
                "type": "totp",
                "name": "alice@example.com",
                "issuer": "Example",
                "info": { "secret": "\(secret)", "algo": "SHA1", "digits": 6, "period": 30 }
              }
            ]
          }
        }
        """
        let tokens = try parse(json)

        XCTAssertEqual(tokens.count, 1)
        XCTAssertEqual(tokens.first?.kind, .totp)
        XCTAssertEqual(tokens.first?.label, "Example")
        XCTAssertEqual(tokens.first?.period, 30)
    }

    func testAnEncryptedAegisExportWithSlotsAndParamsIsStillRefused() throws {
        // The shape of a real encrypted export: key slots and nonce/tag filled in, and
        // `db` a base64 string rather than an object. Letting null values through as
        // plain must not let these through too.
        let json = """
        {
          "version": 1,
          "header": {
            "slots": [{ "type": 1, "uuid": "01234567-89ab-cdef-0123-456789abcdef", "key": "00" }],
            "params": { "nonce": "000000000000000000000000", "tag": "00000000000000000000000000000000" }
          },
          "db": "AAAA"
        }
        """

        XCTAssertThrowsError(try parse(json)) { error in
            XCTAssertEqual(error as? ExternalImportError, .encryptedAegisVault)
        }
    }

    // MARK: - andOTP

    private func andOTPEntry(type: String, counter: String?) -> String {
        let counterField = counter.map { #", "counter": \#($0)"# } ?? ""
        return """
        [
          {
            "type": "\(type)",
            "secret": "\(secret)",
            "issuer": "Example",
            "label": "alice@example.com",
            "algorithm": "SHA1",
            "digits": 6,
            "period": 30\(counterField)
          }
        ]
        """
    }

    func testAnAndOtpHotpEntryIsImportedWithItsCounter() throws {
        let tokens = try parse(andOTPEntry(type: "HOTP", counter: "2"))

        XCTAssertEqual(tokens.count, 1)
        XCTAssertEqual(tokens.first?.kind, .hotp)
        XCTAssertEqual(tokens.first?.counter, 2)
        XCTAssertEqual(tokens.first?.account, "alice@example.com")
    }

    func testAnAndOtpTotpEntryIsUnchanged() throws {
        let tokens = try parse(andOTPEntry(type: "TOTP", counter: nil))

        XCTAssertEqual(tokens.first?.kind, .totp)
        XCTAssertEqual(tokens.first?.period, 30)
    }

    // MARK: - 2FAS

    func testATwoFasHotpEntryIsSkippedRatherThanImportedAtCounterZero() throws {
        // The one format whose HOTP counter field is not documented anywhere this
        // project can check, so the entry is skipped — which is what it did before
        // counter-based codes existed. Importing it at counter 0 would replace a
        // missing code with a code that never works; see the note on the parser.
        let json = """
        {
          "services": [
            {
              "name": "Example",
              "secret": "\(secret)",
              "otp": { "tokenType": "HOTP", "algorithm": "SHA1", "digits": 6, "period": 30 }
            }
          ]
        }
        """

        XCTAssertEqual(try parse(json).count, 0)
    }

    func testTwoFasReadsTheAccountSoTwoAccountsAtOneServiceBothImport() throws {
        // 2FAS keeps the account (and the issuer) inside `otp`. Reading neither made
        // every entry `name` with no account, so a second Google account was the
        // "same token" and was dropped before the import could even count it.
        let json = """
        {
          "services": [
            { "name": "Google", "secret": "\(secret)",
              "otp": { "account": "alice@example.com", "issuer": "Google", "tokenType": "TOTP" } },
            { "name": "Google", "secret": "JBSWY3DPEHPK3PXQ",
              "otp": { "account": "bob@example.com", "issuer": "Google", "tokenType": "TOTP" } }
          ]
        }
        """

        let tokens = try parse(json)

        XCTAssertEqual(tokens.map(\.label), ["Google", "Google"])
        XCTAssertEqual(tokens.map(\.account), ["alice@example.com", "bob@example.com"])
    }

    func testTwoFasFallsBackToTheServiceNameWithoutAnIssuer() throws {
        let json = """
        { "services": [ { "name": "Example", "secret": "\(secret)", "otp": {} } ] }
        """

        let tokens = try parse(json)

        XCTAssertEqual(tokens.first?.label, "Example")
        XCTAssertEqual(tokens.first?.account, "")
    }

    // MARK: - Shared behaviour

    func testASecretTooShortToBeValidIsSkipped() throws {
        // `isValidSecret` is the guard, and it is the same one the add screen uses —
        // a token that could never generate a code must not enter the vault from an
        // import either.
        let json = """
        [ { "type": "TOTP", "secret": "ABC", "issuer": "Example", "label": "a" } ]
        """

        XCTAssertEqual(try parse(json).count, 0)
    }
}

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

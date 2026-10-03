import XCTest
@testable import Vaultic

/// The links any other app, or any web page, can open Autheris with.
///
/// GHSA-75h3-q43q-9338: all three schemes used to write straight into the vault on
/// arrival — with no prompt, and while App Lock was engaged. Parsing is now kept
/// apart from importing, so these tests pin down what a link *decodes to*; the
/// only writer is the Import button in `ImportConfirmationView`.
final class IncomingLinkTests: XCTestCase {

    private func parse(_ string: String) throws -> IncomingLink? {
        IncomingLink.parse(try XCTUnwrap(URL(string: string)))
    }

    private func tokens(_ string: String) throws -> [OTPCode] {
        guard case .tokens(let tokens) = try parse(string) else {
            XCTFail("expected tokens from \(string)")
            return []
        }
        return tokens
    }

    // MARK: - autheris://import

    /// The proof of concept from the advisory, byte for byte. It must decode to
    /// a pending code — shown to the user, label and all — and nothing more.
    func testTheAdvisoryPayloadDecodesToAPendingCode() throws {
        let link = "autheris://import?data=W3siaWQiOiIxMTExMTExMS0yMjIyLTMzMzMtNDQ0NC01NTU1NTU1NTU1NTUiLCJsYWJlbCI6IkdpdEh1YiAiLCJhY2NvdW50IjoieW91QGV4YW1wbGUuY29tIiwic2VjcmV0IjoiSkJTV1kzRFBFSFBLM1BYUCIsImlzUGlubmVkIjp0cnVlfV0"
        let decoded = try tokens(link)
        XCTAssertEqual(decoded.count, 1)
        // The trailing space survives, so the confirmation shows the label as sent.
        XCTAssertEqual(decoded.first?.label, "GitHub ")
        XCTAssertEqual(decoded.first?.account, "you@example.com")
    }

    func testAnExportEnvelopeDecodes() throws {
        let code = OTPCode(label: "Example", account: "a@b.c", secret: "JBSWY3DPEHPK3PXP")
        let export = ExportData(version: "1", timestamp: Date(timeIntervalSince1970: 0), tokens: [code])
        let encoded = try JSONEncoder().encode(export).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        XCTAssertEqual(try tokens("autheris://import?data=\(encoded)").map(\.label), ["Example"])
    }

    func testAnUnreadableImportIsAFailureNotAnEmptyImport() throws {
        guard case .failure = try parse("autheris://import?data=bm90IGpzb24") else {
            return XCTFail("garbage should be reported, not imported")
        }
        guard case .failure = try parse("autheris://import") else {
            return XCTFail("a missing payload should be reported")
        }
        guard case .failure = try parse("autheris://import?data=W10") else {
            return XCTFail("an empty array has nothing to confirm")
        }
    }

    // MARK: - otpauth:// and otpauth-migration://

    func testAnOTPAuthLinkDecodesToOnePendingCode() throws {
        let decoded = try tokens("otpauth://totp/Example:alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Example")
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded.first?.label, "Example")
    }

    func testAnOTPAuthLinkWithABadSecretIsAFailure() throws {
        guard case .failure = try parse("otpauth://totp/Example?secret=not-base32!") else {
            return XCTFail("an invalid secret should be reported")
        }
    }

    func testAnUnreadableMigrationLinkIsAFailure() throws {
        guard case .failure = try parse("otpauth-migration://offline?data=AAAA") else {
            return XCTFail("an unreadable migration should be reported")
        }
    }

    // MARK: - Everything else

    func testLinksThatAreNotOursAreIgnored() throws {
        XCTAssertNil(try parse("https://example.com/import?data=W10"))
        XCTAssertNil(try parse("autheris://settings"))
    }
}

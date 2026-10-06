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

    func testAnImportedCodeWithoutAUsableSetupKeyIsLeftOut() throws {
        let good = OTPCode(label: "Good", account: "a", secret: "JBSWY3DPEHPK3PXP")
        let empty = OTPCode(label: "Empty", account: "b", secret: "")
        let broken = OTPCode(label: "Broken", account: "c", secret: "not base32 at all!")
        let data = try JSONEncoder().encode([good, empty, broken])
        let encoded = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        XCTAssertEqual(try tokens("autheris://import?data=\(encoded)").map(\.label), ["Good"])
    }

    func testAnImportWithNoUsableSetupKeyIsAFailure() throws {
        let data = try JSONEncoder().encode([OTPCode(label: "Empty", account: "b", secret: "")])
        let encoded = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        guard case .failure = try parse("autheris://import?data=\(encoded)") else {
            return XCTFail("nothing usable to import is a failure, not an empty import")
        }
    }

    func testAPaddedSetupKeyInALinkIsAccepted() throws {
        // Base32 padding, as some services write their keys.
        let decoded = try tokens("otpauth://totp/Example:me@example.com?secret=JBSWY3DPEHPK3PXP%3D%3D%3D%3D%3D%3D&issuer=Example")

        XCTAssertEqual(decoded.count, 1)
        let unpadded = OTPCode(label: "Example", account: "me@example.com", secret: "JBSWY3DPEHPK3PXP")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(decoded.first?.code(at: now), unpadded.code(at: now), "the padding carries no bits")
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

    // MARK: - autheris://add

    /// The format AutherisKit opens: a percent-encoded `otpauth://` link.
    func testAnAddLinkDecodesToOnePendingCode() throws {
        let inner = "otpauth://totp/Example:alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Example"
        let encoded = try XCTUnwrap(inner.addingPercentEncoding(withAllowedCharacters: .alphanumerics))
        let decoded = try tokens("autheris://add?uri=\(encoded)")
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded.first?.label, "Example")
        XCTAssertEqual(decoded.first?.account, "alice@example.com")
    }

    /// Byte for byte what AutherisKit's `AutherisSetup.autherisURL()` produces for
    /// issuer "My App" and account "alice@example.com". Third-party apps ship this
    /// format, so a change here breaks them: keep it decoding.
    func testTheAutherisKitLinkDecodes() throws {
        let decoded = try tokens("autheris://add?uri=otpauth%3A%2F%2Ftotp%2FMy%2520App%3Aalice%2540example.com%3Fsecret%3DJBSWY3DPEHPK3PXP%26issuer%3DMy%2520App")
        XCTAssertEqual(decoded.first?.label, "My App")
        XCTAssertEqual(decoded.first?.account, "alice@example.com")
        XCTAssertEqual(decoded.first?.secret, "JBSWY3DPEHPK3PXP")
    }

    func testAnAddLinkWithoutAnOTPAuthLinkIsAFailure() throws {
        guard case .failure = try parse("autheris://add") else {
            return XCTFail("a missing uri should be reported")
        }
        guard case .failure = try parse("autheris://add?uri=https%3A%2F%2Fexample.com") else {
            return XCTFail("only otpauth:// is accepted inside an add link")
        }
        // A batch has its own review path; `add` is for one code.
        guard case .failure = try parse("autheris://add?uri=otpauth-migration%3A%2F%2Foffline%3Fdata%3DAAAA") else {
            return XCTFail("a migration link should not be accepted inside an add link")
        }
        guard case .failure = try parse("autheris://add?uri=otpauth%3A%2F%2Ftotp%2FExample%3Fsecret%3Dnot-base32!") else {
            return XCTFail("an invalid secret should be reported")
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

    // MARK: - Scanned QR codes

    func testAScannedTransferOrExportIsABatchForReview() throws {
        let tokens: [OTPCode] = [OTPCode(label: "GitHub", account: "a", secret: "JBSWY3DPEHPK3PXP"),
                                 OTPCode(label: "GitLab", account: "b", secret: "JBSWY3DPEHPK3PXQ")]
        let export = try JSONEncoder().encode(ExportData(version: "1.0", timestamp: Date(), tokens: tokens))

        // The bare payload older transfer codes held, as Base64 and as JSON text.
        for payload in [export.base64EncodedString(), String(decoding: export, as: UTF8.self)] {
            guard case .tokens(let batch) = IncomingLink.scannedBatch(payload) else {
                return XCTFail("an export must go to review, not be added")
            }
            XCTAssertEqual(batch.map(\.label), ["GitHub", "GitLab"])
        }
    }

    func testAScannedTransferLinkIsABatchAndABrokenOneIsAFailure() {
        let good = "autheris://import?data=W3siaWQiOiIxMTExMTExMS0yMjIyLTMzMzMtNDQ0NC01NTU1NTU1NTU1NTUiLCJsYWJlbCI6IkdpdEh1YiAiLCJhY2NvdW50IjoieW91QGV4YW1wbGUuY29tIiwic2VjcmV0IjoiSkJTV1kzRFBFSFBLM1BYUCIsImlzUGlubmVkIjp0cnVlfV0"
        guard case .tokens = IncomingLink.scannedBatch(good) else {
            return XCTFail("a transfer link must go to review")
        }
        guard case .failure = IncomingLink.scannedBatch("autheris://import?data=not-a-payload") else {
            return XCTFail("a broken transfer link must say so")
        }
        guard case .failure = IncomingLink.scannedBatch("otpauth-migration://offline?data=garbage") else {
            return XCTFail("a broken Google export must say so")
        }
    }

    func testASingleCodeOrASetupKeyIsNotABatch() {
        // These the scanner adds itself, as it always has.
        XCTAssertNil(IncomingLink.scannedBatch("otpauth://totp/GitHub:alice?secret=JBSWY3DPEHPK3PXP"))
        XCTAssertNil(IncomingLink.scannedBatch("JBSWY3DPEHPK3PXP"))
        XCTAssertNil(IncomingLink.scannedBatch("https://example.com"))
    }
}

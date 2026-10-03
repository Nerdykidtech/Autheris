import XCTest
@testable import Vaultic

/// One parser, three callers.
///
/// `otpauth://` URLs reach the app from a scanned QR code, from iOS handing over a
/// "Set Up Codes In → Autheris" link, and from the confirmation sheet. All three used
/// to carry their own copy of this parsing, and none of them read the URL's *host* —
/// which is the only place a setup URL says whether it is `totp` or `hotp`. A
/// counter-based QR therefore became a time-based token whose codes the service
/// rejected, silently, with nothing on screen to suggest why. The host cases below
/// are the ones that were wrong.
// The app target defaults to main-actor isolation, which makes the types under
// test main-actor isolated too.
@MainActor
final class OTPAuthURLParserTests: XCTestCase {

    private func parse(_ string: String) throws -> ParsedOTPAuth {
        let url = try XCTUnwrap(URL(string: string), "not a URL: \(string)")
        return try XCTUnwrap(OTPAuthURLParser.parse(url), "did not parse: \(string)")
    }

    // MARK: - The kind, which lives in the host

    func testAHotpURLIsReadAsCounterBased() throws {
        let parsed = try parse("otpauth://hotp/Example:alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Example&counter=4")

        XCTAssertEqual(parsed.kind, .hotp)
        XCTAssertEqual(parsed.counter, 4)
        XCTAssertEqual(parsed.label, "Example")
        XCTAssertEqual(parsed.account, "alice@example.com")
        XCTAssertEqual(parsed.secret, "JBSWY3DPEHPK3PXP")
    }

    func testATotpURLIsReadAsTimeBased() throws {
        let parsed = try parse("otpauth://totp/Example:alice@example.com?secret=JBSWY3DPEHPK3PXP&period=60")

        XCTAssertEqual(parsed.kind, .totp)
        XCTAssertEqual(parsed.counter, 0)
        XCTAssertEqual(parsed.period, 60)
    }

    func testAnHotpURLWithNoCounterStartsAtZero() throws {
        // The counter is optional in the spec, and RFC 4226 numbers the first code
        // zero. Treating it as absent rather than as an error is what lets a service
        // hand out a bare secret.
        let parsed = try parse("otpauth://hotp/Example?secret=JBSWY3DPEHPK3PXP")

        XCTAssertEqual(parsed.kind, .hotp)
        XCTAssertEqual(parsed.counter, 0)
    }

    func testAHostThisAppDoesNotKnowIsReadAsTimeBased() throws {
        // Anything that is not explicitly `hotp` is time-based: `totp` is the
        // overwhelming majority, and it is also the spec's default. Refusing an
        // unknown host would turn a working setup link into an error.
        XCTAssertEqual(try parse("otpauth://something/Example?secret=JBSWY3DPEHPK3PXP").kind, .totp)
    }

    func testTheHostIsMatchedCaseInsensitively() throws {
        XCTAssertEqual(try parse("otpauth://HOTP/Example?secret=JBSWY3DPEHPK3PXP").kind, .hotp)
    }

    // MARK: - The counter's bounds

    func testACounterOnATimeBasedURLIsIgnored() throws {
        // A time-based code has no counter to honour, and carrying one over would be
        // inventing state the service never asked for — which `OTPCode` would then
        // sync and display.
        let parsed = try parse("otpauth://totp/Example?secret=JBSWY3DPEHPK3PXP&counter=9")

        XCTAssertEqual(parsed.kind, .totp)
        XCTAssertEqual(parsed.counter, 0)
    }

    func testACounterIsClampedToWhatICloudCanCarry() throws {
        // The value goes into a CloudKit `Int64` field, so anything larger would be
        // written as one number and read back as another — a wrong code with nothing
        // to notice it. The input here is a string a stranger wrote.
        XCTAssertEqual(
            try parse("otpauth://hotp/Example?secret=JBSWY3DPEHPK3PXP&counter=9223372036854775808").counter,
            OTPCode.maximumCounter
        )
        XCTAssertEqual(
            try parse("otpauth://hotp/Example?secret=JBSWY3DPEHPK3PXP&counter=\(UInt64.max)").counter,
            OTPCode.maximumCounter
        )
    }

    func testACounterThatIsNotANumberOrIsNegativeMeansZero() throws {
        // `UInt64` refuses both, and both are "the service did not tell us where to
        // start" rather than an error worth refusing the whole code over.
        for raw in ["", "abc", "-1", "1.5"] {
            let parsed = try parse("otpauth://hotp/Example?secret=JBSWY3DPEHPK3PXP&counter=\(raw)")
            XCTAssertEqual(parsed.counter, 0, "counter=\(raw)")
            XCTAssertEqual(parsed.kind, .hotp, "counter=\(raw)")
        }
    }

    // MARK: - A link pasted into the manual form

    func testAPastedSetupLinkIsReadAsAToken() {
        // What a service's website hands you. The manual form used to reject it with
        // "please enter a valid Base32 secret key", because a URL is not Base32.
        let parsed = OTPAuthURLParser.parseLink("otpauth://totp/Example:alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Example")

        XCTAssertEqual(parsed?.label, "Example")
        XCTAssertEqual(parsed?.account, "alice@example.com")
        XCTAssertEqual(parsed?.kind, .totp)
    }

    func testAPastedCounterBasedLinkKeepsItsCounter() {
        // The case that was silently wrong before this release, arriving by paste
        // rather than by scan.
        let parsed = OTPAuthURLParser.parseLink("otpauth://hotp/Example?secret=JBSWY3DPEHPK3PXP&counter=6")

        XCTAssertEqual(parsed?.kind, .hotp)
        XCTAssertEqual(parsed?.counter, 6)
    }

    func testAPastedLinkSurvivesTheWhitespacePastingCollects() {
        // Copied out of a web page or out of a message that wrapped it, so whitespace
        // is the normal case rather than an edge one.
        XCTAssertNotNil(OTPAuthURLParser.parseLink("\n  otpauth://totp/Example?secret=JBSWY3DPEHPK3PXP  \n"))
    }

    func testABareSecretIsNotALink() {
        // The ordinary contents of that field, which the caller handles itself.
        XCTAssertNil(OTPAuthURLParser.parseLink("JBSWY3DPEHPK3PXP"))
        XCTAssertNil(OTPAuthURLParser.parseLink(""))
    }

    func testNeitherATransferLinkNorAWebPageIsASetupLink() {
        // `autheris://import?data=…` carries a whole vault rather than one token, so
        // it belongs to the import flow, not here.
        XCTAssertNil(OTPAuthURLParser.parseLink("autheris://import?data=abc"))
        XCTAssertNil(OTPAuthURLParser.parseLink("https://example.com/?secret=JBSWY3DPEHPK3PXP"))
    }

    func testAPastedLinkWithoutASecretIsNotRead() {
        // The same rule as a scanned one: no secret, no token. The form falls through
        // to its own message rather than saving something empty.
        XCTAssertNil(OTPAuthURLParser.parseLink("otpauth://totp/Example"))
    }

    // MARK: - What still has to be refused

    func testAURLWithoutALabelOrWithoutASecretIsNotParsed() throws {
        // The caller turns this into "that link isn't usable, enter it by hand", so
        // it must stay nil rather than producing a token with an empty field.
        XCTAssertNil(OTPAuthURLParser.parse(try XCTUnwrap(URL(string: "otpauth://totp/?secret=JBSWY3DPEHPK3PXP"))))
        XCTAssertNil(OTPAuthURLParser.parse(try XCTUnwrap(URL(string: "otpauth://totp/Example"))))
    }

    func testANonOtpauthSchemeIsNotParsed() throws {
        XCTAssertNil(OTPAuthURLParser.parse(try XCTUnwrap(URL(string: "https://example.com/?secret=JBSWY3DPEHPK3PXP"))))
        XCTAssertNil(OTPAuthURLParser.parse(try XCTUnwrap(URL(string: "autheris://import?data=abc"))))
    }

    // MARK: - The rest of the fields, which were already parsed

    func testAlgorithmDigitsAndIssuerAreStillRead() throws {
        // The fields the three old copies did agree on, kept here so the single
        // parser is the one place their behaviour is pinned.
        let parsed = try parse("otpauth://totp/Path:acct?secret=JBSWY3DPEHPK3PXP&issuer=Issuer&algorithm=SHA256&digits=8&period=45")

        XCTAssertEqual(parsed.algorithm, .sha256)
        XCTAssertEqual(parsed.digits, 8)
        XCTAssertEqual(parsed.period, 45)
        // The issuer overrides the label from the path, and the account survives.
        XCTAssertEqual(parsed.label, "Issuer")
        XCTAssertEqual(parsed.account, "acct")
    }
}

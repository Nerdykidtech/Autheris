import XCTest
@testable import Vaultic

/// Google Authenticator's export QR (`otpauth-migration://offline?data=…`), which is
/// a URL-encoded, Base64'd protobuf rather than a list of `otpauth://` URLs.
///
/// It has always carried a `type` (1 = HOTP, 2 = TOTP) and a `counter`, and the
/// parser used to read both and then *refuse* every HOTP entry — so a Google
/// Authenticator user with a counter-based account moved to Autheris and quietly
/// arrived without it. Both kinds are covered here, plus the fixtures themselves:
/// the protobuf is built byte by byte rather than pasted as a blob, so a change in
/// how the export is encoded is visible in this file instead of hidden in a blob of
/// Base64.
final class GoogleMigrationParserTests: XCTestCase {

    /// The RFC 4226 reference secret, as ASCII. Google's export carries the *raw*
    /// secret bytes and the parser Base32-encodes them, which is why this is not
    /// written as Base32.
    private let rawSecret = "12345678901234567890"

    // MARK: - A minimal protobuf writer

    private func varint(_ value: Int) -> [UInt8] {
        var remaining = value
        var bytes: [UInt8] = []
        repeat {
            var byte = UInt8(remaining & 0x7F)
            remaining >>= 7
            if remaining != 0 { byte |= 0x80 }
            bytes.append(byte)
        } while remaining != 0
        return bytes
    }

    private func field(_ number: Int, varint value: Int) -> [UInt8] {
        varint((number << 3) | 0) + varint(value)
    }

    private func field(_ number: Int, bytes: [UInt8]) -> [UInt8] {
        varint((number << 3) | 2) + varint(bytes.count) + bytes
    }

    /// `OtpParameters`, wrapped in `MigrationPayload`'s repeated field 1.
    private func export(secret: String,
                        name: String,
                        issuer: String,
                        type: Int,
                        counter: Int) -> String {
        var parameters: [UInt8] = []
        parameters += field(1, bytes: Array(secret.utf8))   // secret
        parameters += field(2, bytes: Array(name.utf8))     // name
        parameters += field(3, bytes: Array(issuer.utf8))   // issuer
        parameters += field(4, varint: 1)                   // algorithm: SHA1
        parameters += field(5, varint: 1)                   // digits: six
        parameters += field(6, varint: type)                // type: 1 = HOTP, 2 = TOTP
        parameters += field(7, varint: counter)             // counter

        let payload = field(1, bytes: parameters)
        let base64 = Data(payload).base64EncodedString()
        // Percent-encoded because the query item is read back through `URLComponents`,
        // and Base64 may carry `=` and `/`.
        let encoded = base64.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? base64
        return "otpauth-migration://offline?data=\(encoded)"
    }

    private func parse(_ url: String) throws -> [OTPCode] {
        try XCTUnwrap(GoogleMigrationParser.parseMigrationURL(url), "did not parse: \(url)")
    }

    // MARK: - Counter-based entries

    func testAnHotpEntryIsImportedWithItsCounterRatherThanDropped() throws {
        let tokens = try parse(export(secret: rawSecret, name: "alice@example.com",
                                      issuer: "Example", type: 1, counter: 5))

        XCTAssertEqual(tokens.count, 1)
        XCTAssertEqual(tokens[0].kind, .hotp)
        XCTAssertEqual(tokens[0].counter, 5)
        // The parser Base32-encodes the raw secret bytes, and the RFC 4226 reference
        // secret encodes to exactly this.
        XCTAssertEqual(tokens[0].secret, "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ")
        XCTAssertEqual(tokens[0].label, "Example")
        XCTAssertEqual(tokens[0].account, "alice@example.com")
    }

    func testACounterPast35BitsIsReadWhole() throws {
        // `int64` on the wire. Varints used to be capped at 35 bits, which every
        // tag and length fits but a counter need not.
        let large = 1 << 40
        let tokens = try parse(export(secret: rawSecret, name: "alice@example.com",
                                      issuer: "Example", type: 1, counter: large))

        XCTAssertEqual(tokens.first?.counter, UInt64(large))
    }

    func testTheImportedHotpEntryGeneratesTheRfc4226CodeForItsCounter() throws {
        // The end of the path that used to be a silent dead end: what arrives has to
        // be a token that actually produces the service's code.
        let token = try parse(export(secret: rawSecret, name: "Example", issuer: "Example",
                                     type: 1, counter: 0))[0]

        XCTAssertEqual(token.currentCode, "755224")
    }

    // MARK: - Time-based entries

    func testATotpEntryIsUnaffectedByTheCounterSupport() throws {
        let tokens = try parse(export(secret: rawSecret, name: "Example", issuer: "Example",
                                      type: 2, counter: 0))

        XCTAssertEqual(tokens[0].kind, .totp)
        // A time-based entry carries no counter, so nothing from field 7 is kept.
        XCTAssertEqual(tokens[0].counter, 0)
        XCTAssertEqual(tokens[0].period, 30)
    }

    func testAnUnsetTypeIsReadAsTimeBased() throws {
        // The protobuf's `unspecified` value is 0, and a field Google itself always
        // writes is only absent when something else produced the file. Time-based is
        // what nearly every entry is, so it is the safe reading.
        var parameters: [UInt8] = []
        parameters += field(1, bytes: Array(rawSecret.utf8))
        parameters += field(2, bytes: Array("Example".utf8))
        let base64 = Data(field(1, bytes: parameters)).base64EncodedString()
        let encoded = base64.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? base64

        let tokens = try parse("otpauth-migration://offline?data=\(encoded)")

        XCTAssertEqual(tokens.count, 1)
        XCTAssertEqual(tokens[0].kind, .totp)
    }

    // MARK: - A mixed export, which is what a real one looks like

    func testAMixedExportKeepsBothKinds() throws {
        var payload: [UInt8] = []

        var hotp: [UInt8] = []
        hotp += field(1, bytes: Array(rawSecret.utf8))
        hotp += field(2, bytes: Array("Counter".utf8))
        hotp += field(6, varint: 1)
        hotp += field(7, varint: 3)
        payload += field(1, bytes: hotp)

        var totp: [UInt8] = []
        totp += field(1, bytes: Array(rawSecret.utf8))
        totp += field(2, bytes: Array("Timed".utf8))
        totp += field(6, varint: 2)
        payload += field(1, bytes: totp)

        let base64 = Data(payload).base64EncodedString()
        let encoded = base64.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? base64

        let tokens = try parse("otpauth-migration://offline?data=\(encoded)")

        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens.map(\.kind), [.hotp, .totp])
        XCTAssertEqual(tokens.map(\.counter), [3, 0])
    }

    // MARK: - What is not one of these

    func testSomethingThatIsNotAMigrationURLIsNotParsed() {
        XCTAssertNil(GoogleMigrationParser.parseMigrationURL("otpauth://totp/Example?secret=JBSWY3DPEHPK3PXP"))
        XCTAssertNil(GoogleMigrationParser.parseMigrationURL("otpauth-migration://offline?data="))
        XCTAssertNil(GoogleMigrationParser.parseMigrationURL("otpauth-migration://offline"))
    }
}

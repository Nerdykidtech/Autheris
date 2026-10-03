import XCTest
import CoreImage
import CoreImage.CIFilterBuiltins
@testable import Vaultic

/// The Transfer QR Code's link, in both formats.
///
/// The full JSON export took about 430 bytes a code, so a QR code held 8 and the
/// transfer screen gave up at the 9th. The compact format has to carry far more,
/// arrive exactly as it left, and still give way to the old format whenever that
/// fits — so a device that hasn't updated can import a small vault.
@MainActor
final class TransferPayloadTests: XCTestCase {

    private func codes(_ count: Int) -> [OTPCode] {
        (0..<count).map { index in
            OTPCode(label: "Service \(index)", account: "user\(index)@example.com",
                    secret: OTPGenerator.encodeBase32(Data((0..<20).map { UInt8(($0 * 7 + index) % 256) })))
        }
    }

    private func importedTokens(_ link: String) throws -> [OTPCode] {
        guard case .tokens(let tokens) = IncomingLink.parse(try XCTUnwrap(URL(string: link))) else {
            XCTFail("the link did not import")
            return []
        }
        return tokens
    }

    // MARK: - Capacity

    func testAFewCodesStillUseTheFormatEveryReleaseReads() throws {
        let link = try XCTUnwrap(TransferPayload.link(for: codes(3)))

        XCTAssertFalse(link.contains("v=2"), "a device that hasn't updated must be able to import this")
        XCTAssertEqual(try importedTokens(link).map(\.label), ["Service 0", "Service 1", "Service 2"])
    }

    func testFarMoreThanEightCodesFitInOneQRCode() throws {
        // Eight was the old limit. Fifty, with typical secrets and accounts.
        let many = codes(50)
        XCTAssertNil(TransferPayload.legacyLink(for: many).flatMap {
            $0.utf8.count <= TransferPayload.maximumQRBytes ? $0 : nil
        }, "fixture: the old format must not fit, or this tests nothing")

        let link = try XCTUnwrap(TransferPayload.link(for: many))

        XCTAssertTrue(link.contains("v=2"))
        XCTAssertLessThanOrEqual(link.utf8.count, TransferPayload.maximumQRBytes)
        XCTAssertEqual(try importedTokens(link).map(\.label), many.map(\.label))
    }

    func testAFullCompactQRCodeStillReadsBack() throws {
        // A QR code this full is dense. Draw it the way `QRCodeView` does — error
        // correction L, about the size it appears on a phone (250 points at 3x) —
        // and read it back. Core Image's detector rather than Vision, which "Upload
        // QR" uses, because Vision can't run in the simulator.
        let link = try XCTUnwrap(TransferPayload.link(for: codes(50)))
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue("L", forKey: "inputCorrectionLevel")
        filter.message = Data(link.utf8)
        let qr = try XCTUnwrap(filter.outputImage)
        let scale = 750 / qr.extent.width
        let drawn = qr.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                        options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]) else {
            throw XCTSkip("No QR detector on this device")
        }
        let found = detector.features(in: drawn).compactMap { ($0 as? CIQRCodeFeature)?.messageString }

        XCTAssertEqual(found, [link])
    }

    func testAVaultTooBigForEvenTheCompactFormatHasNoLink() {
        XCTAssertNil(TransferPayload.link(for: codes(400)))
    }

    // MARK: - Fidelity

    func testEverythingAnImportKeepsSurvivesTheCompactFormat() throws {
        let originals = [
            OTPCode(label: "GitHub", account: "alice@example.com", secret: "JBSWY3DPEHPK3PXP"),
            OTPCode(label: "Bank", account: "", secret: "JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP",
                    algorithm: .sha512, digits: 8, period: 60, timerRingHex: "#FF8800", isPinned: true),
            OTPCode(label: "Counter", account: "bob", secret: "GEZDGNBVGY3TQOJQ",
                    algorithm: .sha256, kind: .hotp, counter: 1_234_567),
            OTPCode(label: "Ünïcødé 🔐", account: "名前", secret: "MFRGGZDFMZTWQ2LK"),
            // Not in canonical Base32 form — lowercase and spaced — so it has to
            // travel as text to arrive as it left.
            OTPCode(label: "Messy", account: "x", secret: "jbsw y3dp ehpk 3pxp"),
        ]

        let link = try XCTUnwrap(TransferPayload.compactLink(for: originals))
        let decoded = try importedTokens(link)

        XCTAssertEqual(decoded.count, originals.count)
        for (original, copy) in zip(originals, decoded) {
            XCTAssertEqual(copy.label, original.label)
            XCTAssertEqual(copy.account, original.account)
            XCTAssertEqual(copy.secret, original.secret)
            XCTAssertEqual(copy.algorithm, original.algorithm)
            XCTAssertEqual(copy.digits, original.digits)
            XCTAssertEqual(copy.period, original.period)
            XCTAssertEqual(copy.kind, original.kind)
            XCTAssertEqual(copy.counter, original.counter)
            XCTAssertEqual(copy.timerRingHex, original.timerRingHex)
            XCTAssertEqual(copy.isPinned, original.isPinned)
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            XCTAssertEqual(copy.code(at: now), original.code(at: now), "\(original.label) must produce the same codes")
        }
    }

    // MARK: - Hostile input

    func testMalformedCompactPayloadsAreRefusedNotTrusted() {
        let valid = TransferPayload.encode(codes(3))

        XCTAssertNil(TransferPayload.decode(Data()), "empty")
        XCTAssertNil(TransferPayload.decode(Data([1]) + valid.dropFirst()), "wrong format version")
        XCTAssertNil(TransferPayload.decode(valid.dropLast()), "truncated")
        XCTAssertNil(TransferPayload.decode(valid + Data([0])), "trailing bytes")
        // A count far beyond what the bytes could hold.
        XCTAssertNil(TransferPayload.decode(Data([2, 0xFF, 0xFF, 0xFF, 0x0F])), "inflated count")
        // A string length that runs past the end.
        XCTAssertNil(TransferPayload.decode(Data([2, 1, 0, 0x7F, 0x41])), "overlong field")
        XCTAssertNil(TransferPayload.decodeCompact(Data("not deflate".utf8)), "not compressed")
    }

    func testABrokenCompactLinkIsAFailureNotAnImport() throws {
        let link = try XCTUnwrap(URL(string: "autheris://import?v=2&data=AAAA"))
        guard case .failure = IncomingLink.parse(link) else {
            return XCTFail("a link that doesn't decode must say so")
        }
    }
}

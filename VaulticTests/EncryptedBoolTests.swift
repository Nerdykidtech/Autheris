import XCTest
@testable import Vaultic

/// `EncryptedBool` is the only part of the `isPinned` round trip that can be
/// exercised without a CloudKit container, and it is the part that decides
/// whether a pinned code stays pinned. The lenient read matters most: it is what
/// stops an unexpected stored form from taking a whole record down with it.
final class EncryptedBoolTests: XCTestCase {

    func testEncodesAsOneAndZero() {
        XCTAssertEqual(EncryptedBool.text(true), "1")
        XCTAssertEqual(EncryptedBool.text(false), "0")
    }

    func testRoundTripsBothWays() {
        XCTAssertTrue(EncryptedBool.value(EncryptedBool.text(true)))
        XCTAssertFalse(EncryptedBool.value(EncryptedBool.text(false)))
    }

    // MARK: - Lenient reads

    func testAMissingValueReadsAsNotPinned() {
        // Every record written before this field existed stores nothing at all.
        XCTAssertFalse(EncryptedBool.value(nil))
        XCTAssertFalse(EncryptedBool.value(NSNull()))
    }

    func testTheIntegerFormIsAcceptedToo() {
        // Defensive: a development container that created the field as Int64 must
        // not report every pin as `false`.
        XCTAssertTrue(EncryptedBool.value(NSNumber(value: true)))
        XCTAssertFalse(EncryptedBool.value(NSNumber(value: false)))
        XCTAssertTrue(EncryptedBool.value(1))
        XCTAssertFalse(EncryptedBool.value(0))
    }

    func testTheTextualTrueIsAcceptedCaseInsensitively() {
        XCTAssertTrue(EncryptedBool.value("true"))
        XCTAssertTrue(EncryptedBool.value("TRUE"))
    }

    func testUnrecognisedValuesReadAsNotPinnedRatherThanFailing() {
        // A throwing reader would make `decode` skip the entire record.
        for raw in ["yes", "maybe", "", "2", "-1", Data([0x01]), [1, 2, 3]] as [Any] {
            XCTAssertFalse(EncryptedBool.value(raw), "unexpectedly true for \(raw)")
        }
    }
}

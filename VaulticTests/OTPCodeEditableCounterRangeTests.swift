import XCTest
@testable import Vaultic

/// The counters Edit Token offers for a counter-based code.
///
/// A counter only moves forward, so the range starts at the code's own counter.
/// And a counter can be as large as `OTPCode.maximumCounter` — an `otpauth://`
/// link may ask for exactly that — so the top of the range must be worked out
/// without overflowing: a plain `+` there trapped as soon as the screen opened.
final class OTPCodeEditableCounterRangeTests: XCTestCase {

    private func code(counter: UInt64) -> OTPCode {
        OTPCode(label: "Bank", account: "user", secret: "JBSWY3DPEHPK3PXP",
                kind: .hotp, counter: counter)
    }

    func testANewCounterCanBeRaisedButNotLowered() {
        XCTAssertEqual(code(counter: 0).editableCounterRange, 0...10_000)
    }

    func testTheRangeStartsAtTheCounterTheCodeHasNow() {
        XCTAssertEqual(code(counter: 3).editableCounterRange, 3...10_003)
    }

    func testACounterAlreadyPastTenThousandIsInsideItsOwnRange() {
        let range = code(counter: 12_000).editableCounterRange

        XCTAssertEqual(range, 12_000...22_000)
        XCTAssertTrue(range.contains(12_000))
    }

    func testTheLargestCounterAnImportCanSetDoesNotOverflow() {
        // What `otpauth://hotp/…&counter=9223372036854775807` imports as.
        let range = code(counter: OTPCode.maximumCounter).editableCounterRange

        XCTAssertEqual(range, Int.max...Int.max)
    }

    func testACounterJustBelowTheLimitStopsAtTheLimit() {
        let range = code(counter: OTPCode.maximumCounter - 5).editableCounterRange

        XCTAssertEqual(range.lowerBound, Int.max - 5)
        XCTAssertEqual(range.upperBound, Int.max)
    }
}

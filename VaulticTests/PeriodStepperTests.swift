import XCTest
@testable import Vaultic

/// The period stepper steps through multiples of 15 seconds, even from a
/// period that isn't one.
final class PeriodStepperTests: XCTestCase {

    func testAUsualPeriodStepsBy15() {
        XCTAssertEqual(PeriodStepper.stepped(30, up: true, in: 15...300), 45)
        XCTAssertEqual(PeriodStepper.stepped(30, up: false, in: 15...300), 15)
    }

    func testAnUnusualPeriodSnapsToTheNextMultiple() {
        XCTAssertEqual(PeriodStepper.stepped(10, up: true, in: 10...300), 15)
        XCTAssertEqual(PeriodStepper.stepped(20, up: true, in: 15...300), 30)
        XCTAssertEqual(PeriodStepper.stepped(20, up: false, in: 15...300), 15)
    }

    func testItCanStepBackToTheTokensOwnPeriod() {
        XCTAssertEqual(PeriodStepper.stepped(15, up: false, in: 10...300), 10)
        XCTAssertEqual(PeriodStepper.stepped(300, up: true, in: 15...310), 310)
    }

    func testItStaysInsideTheRange() {
        XCTAssertEqual(PeriodStepper.stepped(15, up: false, in: 15...300), 15)
        XCTAssertEqual(PeriodStepper.stepped(300, up: true, in: 15...300), 300)
    }

    func testTheLargestPeriodALinkCanCarryDoesNotOverflow() {
        XCTAssertEqual(PeriodStepper.stepped(Int.max, up: true, in: 15...Int.max), Int.max)
        XCTAssertEqual(PeriodStepper.stepped(Int.max - 5, up: true, in: 15...Int.max), Int.max)
        XCTAssertEqual(PeriodStepper.stepped(Int.max, up: false, in: 15...Int.max), Int.max / 15 * 15)
    }
}

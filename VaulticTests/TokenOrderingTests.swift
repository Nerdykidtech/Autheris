import XCTest
@testable import Vaultic

/// `TokenOrdering` is the only thing standing between a drag and the user's list,
/// and it has to reconcile two rules that pull against each other: pinned codes
/// sort to the top, and a drag says exactly where the code should go. The cases
/// where those disagree are the interesting ones.
final class TokenOrderingTests: XCTestCase {

    private func token(_ label: String, pinned: Bool = false) -> OTPCode {
        OTPCode(label: label, account: "acct", secret: "JBSWY3DPEHPK3PXP", isPinned: pinned)
    }

    private func labels(_ tokens: [OTPCode]) -> [String] { tokens.map(\.label) }

    // MARK: - Display order

    func testPinnedCodesSortToTheTopKeepingRelativeOrder() {
        let tokens = [token("A"), token("B", pinned: true), token("C"), token("D", pinned: true)]

        XCTAssertEqual(labels(TokenOrdering.displayed(tokens)), ["B", "D", "A", "C"])
    }

    func testNothingPinnedLeavesTheOrderAlone() {
        let tokens = [token("A"), token("B"), token("C")]

        XCTAssertEqual(labels(TokenOrdering.displayed(tokens)), ["A", "B", "C"])
    }

    func testEverythingPinnedLeavesTheOrderAlone() {
        let tokens = [token("A", pinned: true), token("B", pinned: true)]

        XCTAssertEqual(labels(TokenOrdering.displayed(tokens)), ["A", "B"])
    }

    func testAnEmptyListStaysEmpty() {
        XCTAssertTrue(TokenOrdering.displayed([]).isEmpty)
    }

    func testDisplayedIsIdempotentSoCallersMayNormaliseFreely() {
        let tokens = [token("A"), token("B", pinned: true), token("C"), token("D", pinned: true)]

        let once = TokenOrdering.displayed(tokens)

        XCTAssertEqual(labels(TokenOrdering.displayed(once)), labels(once))
        XCTAssertEqual(TokenOrdering.displayed(once).map(\.id), once.map(\.id))
    }

    // MARK: - Moving

    func testMovingToTheTop() {
        let tokens = [token("A"), token("B"), token("C")]

        let moved = TokenOrdering.moving(tokens, offsets: IndexSet(integer: 2), destination: 0)

        XCTAssertEqual(labels(moved), ["C", "A", "B"])
    }

    func testMovingToTheBottom() {
        let tokens = [token("A"), token("B"), token("C")]

        let moved = TokenOrdering.moving(tokens, offsets: IndexSet(integer: 0), destination: 3)

        XCTAssertEqual(labels(moved), ["B", "C", "A"])
    }

    func testMovingDownAmongNeighbours() {
        let tokens = [token("A"), token("B"), token("C"), token("D")]

        // Drag B (index 1) to sit after C — SwiftUI reports the destination as an
        // insertion point in the array as it was before the drag.
        let moved = TokenOrdering.moving(tokens, offsets: IndexSet(integer: 1), destination: 3)

        XCTAssertEqual(labels(moved), ["A", "C", "B", "D"])
    }

    func testADestinationEqualTotheIndicesIsANoOp() {
        let tokens = [token("A"), token("B"), token("C")]

        // Destination 1 and 2 both mean "leave B where it is".
        XCTAssertEqual(labels(TokenOrdering.moving(tokens, offsets: IndexSet(integer: 1), destination: 1)),
                       ["A", "B", "C"])
        XCTAssertEqual(labels(TokenOrdering.moving(tokens, offsets: IndexSet(integer: 1), destination: 2)),
                       ["A", "B", "C"])
    }

    func testADestinationPastTheEndIsClamped() {
        let tokens = [token("A"), token("B")]

        let moved = TokenOrdering.moving(tokens, offsets: IndexSet(integer: 0), destination: 99)

        XCTAssertEqual(labels(moved), ["B", "A"])
    }

    func testOutOfRangeOffsetsAreIgnoredRatherThanCrashing() {
        let tokens = [token("A"), token("B")]

        XCTAssertEqual(labels(TokenOrdering.moving(tokens, offsets: IndexSet(integer: 9), destination: 0)),
                       ["A", "B"])
        XCTAssertEqual(labels(TokenOrdering.moving(tokens, offsets: IndexSet(), destination: 0)),
                       ["A", "B"])
    }

    func testMovingSeveralCodesAtOnceCarriesThemTogether() {
        let tokens = [token("A"), token("B"), token("C"), token("D")]

        // A and C selected, dropped after D.
        let moved = TokenOrdering.moving(tokens, offsets: IndexSet([0, 2]), destination: 4)

        XCTAssertEqual(labels(moved), ["B", "D", "A", "C"])
    }

    // MARK: - Moving across the pin boundary

    func testAnUnpinnedCodeDroppedAboveAPinSettlesJustBelowIt() {
        // Pinned-first is not something a drag can override — this is the one
        // place where the drag does not go exactly where the user aimed, so it is
        // worth pinning down explicitly.
        let tokens = [token("Pinned", pinned: true), token("A"), token("B")]

        let moved = TokenOrdering.moving(tokens, offsets: IndexSet(integer: 2), destination: 0)

        XCTAssertEqual(labels(moved), ["Pinned", "B", "A"])
    }

    func testMovingWithinThePinnedGroupKeepsEverythingPinned() {
        let tokens = [token("P1", pinned: true), token("U1"), token("P2", pinned: true)]

        // Displayed order is [P1, P2, U1]; drag P2 (displayed index 1) to the top.
        let moved = TokenOrdering.moving(tokens, offsets: IndexSet(integer: 1), destination: 0)

        XCTAssertEqual(labels(moved), ["P2", "P1", "U1"])
        XCTAssertTrue(moved.prefix(2).allSatisfy(\.isPinned))
    }

    func testMovingPreservesEachCodesIdentityAndPinFlag() {
        let pinned = token("P", pinned: true)
        let plain = token("U")

        let moved = TokenOrdering.moving([plain, pinned], offsets: IndexSet(integer: 1), destination: 0)

        XCTAssertEqual(labels(moved), ["P", "U"])
        XCTAssertEqual(Set(moved.map(\.id)), Set([pinned.id, plain.id]))
        XCTAssertTrue(moved[0].isPinned)
        XCTAssertFalse(moved[1].isPinned)
    }

    /// The property that matters most: a drag must never lose or duplicate a code.
    func testEveryPossibleSingleMoveKeepsTheSameSetOfCodes() {
        let tokens = [token("A"), token("B", pinned: true), token("C"), token("D")]
        let originalIDs = Set(tokens.map(\.id))

        for from in tokens.indices {
            for destination in 0...tokens.count {
                let moved = TokenOrdering.moving(tokens,
                                                 offsets: IndexSet(integer: from),
                                                 destination: destination)

                XCTAssertEqual(moved.count, tokens.count,
                               "from \(from) to \(destination) changed the count")
                XCTAssertEqual(Set(moved.map(\.id)), originalIDs,
                               "from \(from) to \(destination) changed which codes are present")
            }
        }
    }

    func testMovingAlwaysLeavesTheListInDisplayOrder() {
        let tokens = [token("A", pinned: true), token("B"), token("C", pinned: true), token("D")]

        for from in tokens.indices {
            let moved = TokenOrdering.moving(tokens,
                                             offsets: IndexSet(integer: from),
                                             destination: 0)

            XCTAssertEqual(labels(moved), labels(TokenOrdering.displayed(moved)),
                           "from \(from) left the list un-normalised")
        }
    }
}

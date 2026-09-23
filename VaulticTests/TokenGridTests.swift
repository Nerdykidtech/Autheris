import XCTest
@testable import Vaultic

/// The grid rules decide what an iPad shows and which slot a carried card lands
/// in. The slot maths is the one worth asserting directly: an off-by-one files a
/// code one place away from the finger, which reads as a bug in the drag rather
/// than in the arithmetic.
final class TokenGridTests: XCTestCase {

    private let cellSize = CGSize(width: 400, height: 80)
    private var spacing: CGFloat { TokenGrid.cardSpacing }

    private func slot(atX x: CGFloat, y: CGFloat, columns: Int = 2, count: Int = 6) -> Int {
        TokenGrid.slotIndex(at: CGPoint(x: x, y: y),
                            cellSize: cellSize,
                            columns: columns,
                            spacing: spacing,
                            count: count)
    }

    // MARK: - Columns

    func testAnIPadWideEnoughForTwoCardsGetsTwoColumns() {
        XCTAssertEqual(TokenGrid.columns(forWidth: 1032), 2)
    }

    func testTwoColumnsStartExactlyAtTheMinimumWidth() {
        XCTAssertEqual(TokenGrid.columns(forWidth: TokenGrid.twoColumnMinimumWidth), 2)
        XCTAssertEqual(TokenGrid.columns(forWidth: TokenGrid.twoColumnMinimumWidth - 1), 1)
    }

    func testANarrowIPadKeepsOneColumn() {
        // Slide Over and a narrow Split View land here: two cards would be cramped.
        XCTAssertEqual(TokenGrid.columns(forWidth: 320), 1)
    }

    func testAnIPhoneWidthStaysOneColumn() {
        XCTAssertEqual(TokenGrid.columns(forWidth: 390), 1)
    }

    func testALandscapeIPadStaysTwoColumns() {
        // The grid is capped at `maximumContentWidth`, so the width it is asked
        // about never reaches a 13" iPad's full 1376pt — and two cards is the
        // answer either way.
        XCTAssertEqual(TokenGrid.columns(forWidth: TokenGrid.maximumContentWidth), 2)
    }

    // MARK: - The slot under the finger

    func testAPointInTheFirstCardIsTheFirstSlot() {
        XCTAssertEqual(slot(atX: 10, y: 10), 0)
    }

    func testAPointInTheSecondColumnOfTheFirstRowIsTheSecondSlot() {
        XCTAssertEqual(slot(atX: cellSize.width + spacing + 10, y: 10), 1)
    }

    func testAPointOnTheNextRowSkipsAColumnsWorthOfSlots() {
        let secondRowY = cellSize.height + spacing + 10

        XCTAssertEqual(slot(atX: 10, y: secondRowY), 2)
        XCTAssertEqual(slot(atX: cellSize.width + spacing + 10, y: secondRowY), 3)
    }

    func testAPointAboveOrBesideTheGridClampsToTheFirstSlot() {
        XCTAssertEqual(slot(atX: -200, y: -200), 0)
    }

    func testAPointPastTheEndClampsToTheLastSlot() {
        // Which is what lets a card be carried past the last code: the end of the
        // list is a slot like any other.
        XCTAssertEqual(slot(atX: 10, y: 5_000, count: 6), 5)
        XCTAssertEqual(slot(atX: 10, y: 5_000, count: 5), 4)
    }

    func testASingleColumnCountsOneSlotPerRow() {
        XCTAssertEqual(slot(atX: 10, y: cellSize.height + spacing + 1, columns: 1, count: 4), 1)
    }

    // MARK: - From the slot the finger is over to the move the list makes

    func testACardCarriedForwardsAsksForOneSlotFurtherOn() {
        // The insertion point is measured before the card is lifted out, so a card
        // on its way forwards must ask for the slot after the one it is over.
        XCTAssertEqual(TokenGrid.insertionIndex(hoveringSlot: 3, liftedFrom: 1), 4)
    }

    func testACardCarriedBackwardsAsksForTheSlotItIsOver() {
        XCTAssertEqual(TokenGrid.insertionIndex(hoveringSlot: 1, liftedFrom: 3), 1)
    }

    func testACardOverItsOwnSlotAsksForNoMove() {
        XCTAssertEqual(TokenGrid.insertionIndex(hoveringSlot: 2, liftedFrom: 2), 2)
    }

    /// The property the whole drag rests on: whatever slot the finger is over, the
    /// carried code ends up in that slot — forwards, backwards, first and last.
    func testACarriedCodeEndsUpInTheSlotItIsOver() {
        let tokens = ["A", "B", "C", "D", "E"].map { OTPCode(label: $0, account: "acct", secret: "JBSWY3DPEHPK3PXP") }

        for lifted in tokens.indices {
            for hovered in tokens.indices {
                let destination = TokenGrid.insertionIndex(hoveringSlot: hovered, liftedFrom: lifted)
                let moved = TokenOrdering.moving(tokens, id: tokens[lifted].id, to: destination)

                XCTAssertEqual(moved.firstIndex { $0.id == tokens[lifted].id }, hovered,
                               "\(tokens[lifted].label) lifted from \(lifted) over slot \(hovered) "
                               + "landed in \(moved.firstIndex { $0.id == tokens[lifted].id } ?? -1)")
            }
        }
    }

    func testUnmeasuredCellsAndEmptyGridsAnswerTheFirstSlot() {
        // Before a card has reported its size, or with nothing to reorder, this has
        // to answer something rather than divide by zero.
        XCTAssertEqual(TokenGrid.slotIndex(at: CGPoint(x: 100, y: 100),
                                           cellSize: .zero,
                                           columns: 2, spacing: spacing, count: 5), 0)
        XCTAssertEqual(TokenGrid.slotIndex(at: CGPoint(x: 100, y: 100),
                                           cellSize: cellSize,
                                           columns: 2, spacing: spacing, count: 0), 0)
        XCTAssertEqual(TokenGrid.slotIndex(at: CGPoint(x: 100, y: 100),
                                           cellSize: cellSize,
                                           columns: 0, spacing: spacing, count: 5), 0)
    }
}

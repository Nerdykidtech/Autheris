import Foundation

/// How the codes are arranged on an iPad, and which slot a carried card lands in.
///
/// Kept free of SwiftUI so the rules that are easy to get subtly wrong — how many
/// cards fit across, which slot the finger is over, and the index that slot means
/// to the list — can be asserted in tests without a simulator.
nonisolated enum TokenGrid {

    /// Two cards side by side once the display is at least this wide.
    ///
    /// 640 leaves each card roughly the width it has on an iPhone, which is the
    /// width the card was designed for. Below it — a narrow Split View, or Slide
    /// Over — one column is the honest layout rather than two cramped ones.
    static let twoColumnMinimumWidth: CGFloat = 640

    /// The widest the grid may grow.
    ///
    /// A 13" iPad in landscape offers 1376pt across. Two cards stretched over all
    /// of it would be mostly empty space, so the grid stops here and centres
    /// itself instead.
    static let maximumContentWidth: CGFloat = 1100

    /// The gap between cards, horizontally and vertically.
    static let cardSpacing: CGFloat = 16

    /// Trailing space a card leaves for the reorder grabber while it is being
    /// rearranged, so the handle does not sit on top of the countdown.
    static let grabberSpace: CGFloat = 44

    /// How many cards to show per row.
    static func columns(forWidth width: CGFloat) -> Int {
        width >= twoColumnMinimumWidth ? 2 : 1
    }

    /// The insertion point that puts a carried card in the slot it is over.
    ///
    /// `TokenOrdering.moving` takes an insertion point in the list *before* the
    /// card is lifted out of it, so a card carried forwards has to ask for one slot
    /// further on than the slot it is over. Without that it settles a slot behind
    /// the finger — the classic off-by-one, and the one thing that makes a live
    /// drag feel wrong.
    static func insertionIndex(hoveringSlot slot: Int, liftedFrom currentIndex: Int) -> Int {
        slot > currentIndex ? slot + 1 : slot
    }

    /// The slot a point falls in, clamped to the codes that exist.
    ///
    /// This is what makes the grid rearrange under the finger: the slot the finger
    /// is over is where the carried card would land if it were let go, and the grid
    /// is reordered to that live. Clamping is what lets a card be carried past the
    /// last code without asking for a slot that does not exist — the end of the
    /// list is the last slot.
    static func slotIndex(at point: CGPoint,
                          cellSize: CGSize,
                          columns: Int,
                          spacing: CGFloat,
                          count: Int) -> Int {
        guard count > 0, columns > 0, cellSize.width > 0, cellSize.height > 0 else { return 0 }

        let column = min(max(Int(floor(point.x / (cellSize.width + spacing))), 0), columns - 1)
        let row = max(Int(floor(point.y / (cellSize.height + spacing))), 0)
        return min(row * columns + column, count - 1)
    }
}

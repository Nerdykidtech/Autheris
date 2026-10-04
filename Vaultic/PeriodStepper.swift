import SwiftUI

/// The period stepper on the Add and Edit screens.
///
/// Steps through multiples of 15 seconds, the periods services actually use.
/// A plain `Stepper(step: 15)` adds 15 to whatever is there, so a token set up
/// with an unusual period — 10 or 20 seconds — went 10 → 25 → 40 and could never
/// get back to 30. This snaps to the next multiple instead, and still reaches
/// the ends of `range`, which may include that unusual period.
struct PeriodStepper: View {
    @Binding var period: Int
    let range: ClosedRange<Int>

    var body: some View {
        // A direction with nowhere to go is passed as `nil`, which disables that
        // button — as the value-based `Stepper` this replaced did at each end.
        Stepper("Period: \(period) seconds",
                onIncrement: period < range.upperBound
                    ? { period = Self.stepped(period, up: true, in: range) } : nil,
                onDecrement: period > range.lowerBound
                    ? { period = Self.stepped(period, up: false, in: range) } : nil)
    }

    /// The next multiple of `step` above or below `period`, kept inside `range`.
    ///
    /// Nothing caps a period from above — a link may carry one as large as `Int`
    /// allows, and its codes still generate — and `range` widens to take it, so
    /// the next multiple up can be past `Int.max`. That stops at the top of the
    /// range rather than trapping.
    nonisolated static func stepped(_ period: Int, up: Bool, in range: ClosedRange<Int>, step: Int = 15) -> Int {
        let (multiple, overflowed) = (up ? period / step + 1 : (period - 1) / step)
            .multipliedReportingOverflow(by: step)
        let next = overflowed ? range.upperBound : multiple
        return min(max(next, range.lowerBound), range.upperBound)
    }
}

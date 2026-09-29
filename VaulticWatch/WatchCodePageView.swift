import SwiftUI

/// One code, filling the screen.
///
/// Read-only by construction. There is no tap target, no context menu and no
/// copy: the phone owns the codes, and the watch exists so a code can be read
/// without taking the phone out of a pocket.
struct WatchCodePageView: View {
    let token: OTPCode

    /// Ticks once a second.
    ///
    /// Anchored at the epoch rather than at "now" so every tick lands on a whole
    /// second. A TOTP period is a whole number of seconds counted from the epoch,
    /// so an epoch-aligned tick is aligned with the period boundary — which is why
    /// the code and its ring change together, on the second they are supposed to,
    /// rather than up to a second late in either direction.
    private static let tick = PeriodicTimelineSchedule(from: Date(timeIntervalSince1970: 0), by: 1)

    /// Where the code starts reading as about to expire.
    ///
    /// The same rule as `HomeView` — five seconds, or a sixth of a longer period —
    /// so the phone and the watch turn red together instead of disagreeing.
    private var warningThreshold: Int {
        max(5, Int(Double(token.effectivePeriod) * 0.1667))
    }

    /// The countdown ring's tint: the token's own colour when one was picked in
    /// the phone app, and the accent otherwise.
    ///
    /// The phone additionally falls back to an issuer brand colour
    /// (`IssuerBranding`), which is deliberately *not* replicated here: that type
    /// also carries logo fetching and its caches, none of which belongs on a
    /// watch. A token with no custom colour is therefore the accent on the watch
    /// and a brand colour on the phone — the one place the two deliberately
    /// differ.
    private var ringColor: Color {
        token.timerRingHex.flatMap(Color.init(hex:)) ?? .accentColor
    }

    var body: some View {
        TimelineView(Self.tick) { context in
            let remaining = Self.remainingSeconds(for: token, at: context.date)
            let isExpiring = remaining <= warningThreshold
            let tint: Color = isExpiring ? .red : ringColor

            VStack(spacing: 2) {
                Text(token.label)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if !token.account.isEmpty {
                    Text(token.account)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                Spacer(minLength: 4)

                Text(Self.code(for: token, at: context.date))
                    .font(.system(size: 42, weight: .semibold, design: .rounded))
                    // Tabular figures, so the code does not change width as its
                    // digits change and shuffle the row underneath it every second.
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(isExpiring ? Color.red : Color.primary)

                Spacer(minLength: 4)

                HStack(spacing: 6) {
                    WatchCountdownRing(
                        progress: Self.progress(remaining: remaining, period: token.effectivePeriod),
                        color: tint
                    )

                    Text("\(remaining)s")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(isExpiring ? Color.red : Color.secondary)
                }
            }
            // Reserve the trailing column the paging dots live in.
            //
            // `verticalPage` draws its indicator *over* the page content, near the
            // trailing edge — about the last 15 pt of the display. A six-digit code
            // at 42 pt is ~144 pt wide and never reaches it, but an eight-digit one
            // is ~192 pt, which on a 211 pt-wide watch would run straight under the
            // dots. Symmetric rather than trailing-only so the code stays centred,
            // which is what the round display wants.
            .padding(.horizontal, Self.dotsGutter)
        }
    }

    /// Space kept clear on each side for the paging indicator and the screen edge.
    private static let dotsGutter: CGFloat = 18

    // MARK: - The clock

    /// Generate for the moment on screen rather than for `Date()`.
    ///
    /// `OTPCode.currentCode` reads the clock itself, which is exactly right on the
    /// phone, where a row is redrawn when a timer fires. Here the moment comes
    /// from the timeline, so the code shown is always the code for the instant the
    /// countdown beside it is counting down to — the two cannot disagree even by a
    /// frame.
    private static func code(for token: OTPCode, at date: Date) -> String {
        OTPGenerator.generateOTP(
            secret: token.secret,
            algorithm: token.algorithm,
            digits: token.effectiveDigits,
            period: token.effectivePeriod,
            now: date
        )
    }

    /// Seconds left in the current period.
    ///
    /// Deliberately the same arithmetic as `HomeView.updateRemainingSeconds`, so
    /// the two devices count down in step. With an epoch-aligned tick the result
    /// runs `period` down to `1` and never reaches `0`, because a whole-second
    /// reading of a whole-second period never lands exactly on the boundary.
    private static func remainingSeconds(for token: OTPCode, at date: Date) -> Int {
        let period = Double(token.effectivePeriod)
        let elapsed = date.timeIntervalSince1970.truncatingRemainder(dividingBy: period)
        return Int(period - elapsed)
    }

    private static func progress(remaining: Int, period: Int) -> Double {
        // `effectivePeriod` is always positive, so this cannot divide by zero even
        // for a token whose stored period was malformed — the same guarantee
        // `HomeView.countdownProgress` relies on.
        min(max(Double(remaining) / Double(period), 0), 1)
    }
}

/// The shrinking ring under the code.
private struct WatchCountdownRing: View {
    let progress: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.22), lineWidth: 3)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                // Start at twelve o'clock and sweep clockwise, the way a countdown
                // is read.
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 22, height: 22)
    }
}

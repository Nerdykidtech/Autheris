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
        if token.isTimeBased {
            // Only a time-based page has something to tick towards, so only a
            // time-based page gets a schedule. Handing a counter-based one the same
            // once-a-second tick would be a wake every second to redraw a page that
            // cannot have changed — on a watch that is battery, not just noise. A
            // counter-based page is redrawn when the phone sends a new payload.
            TimelineView(Self.tick) { context in
                page(code: Self.code(for: token, at: context.date),
                     footer: .seconds(Self.remainingSeconds(for: token, at: context.date)))
            }
        } else {
            page(code: Self.code(for: token, at: Date()),
                 footer: .counter(token.counter))
        }
    }

    /// What sits under the code: how long it has left, or which counter it is.
    private enum Footer {
        case seconds(Int)
        case counter(UInt64)
    }

    /// The page itself, identical for both kinds apart from what is under the code.
    private func page(code: String, footer: Footer) -> some View {
        // A counter-based code has no expiry, so nothing about the page reads as
        // about to expire: no red, and no threshold to cross.
        let isExpiring: Bool
        if case .seconds(let remaining) = footer {
            isExpiring = remaining <= warningThreshold
        } else {
            isExpiring = false
        }
        let tint: Color = isExpiring ? .red : ringColor

        return VStack(spacing: 2) {
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

            Text(code)
                .font(.system(size: 42, weight: .semibold, design: .rounded))
                // Tabular figures, so the code does not change width as its
                // digits change and shuffle the row underneath it every second.
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(isExpiring ? Color.red : Color.primary)

            Spacer(minLength: 4)

            switch footer {
            case .seconds(let remaining):
                HStack(spacing: 6) {
                    WatchCountdownRing(
                        progress: Self.progress(remaining: remaining, period: token.effectivePeriod),
                        color: tint
                    )

                    Text("\(remaining)s")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(isExpiring ? Color.red : Color.secondary)
                }

            case .counter(let counter):
                // No ring and no seconds, because nothing here is expiring: this
                // code is good until the service says otherwise. What the user needs
                // to know instead is which counter they are looking at — the number
                // the service's own prompt may quote — and that the watch cannot
                // move it, because advancing a counter is a write and the watch has
                // no writes by design.
                VStack(spacing: 1) {
                    // `Int` so the watch catalog's key is `Counter %lld`, matching the
                    // app's; the value is bounded by `OTPCode.maximumCounter`.
                    Text("Counter \(Int(clamping: counter))")
                        .font(.caption.monospacedDigit())

                    Text("Advance the counter on your iPhone")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
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
    ///
    /// - Parameter date: Ignored for a counter-based token, whose code does not
    ///   depend on the clock at all. The parameter is kept rather than split into a
    ///   second function so that the two kinds cannot end up rendered through two
    ///   different paths that drift.
    private static func code(for token: OTPCode, at date: Date) -> String {
        guard token.isTimeBased else {
            return OTPGenerator.generateHOTP(
                secret: token.secret,
                algorithm: token.algorithm,
                digits: token.effectiveDigits,
                counter: token.counter
            )
        }

        return OTPGenerator.generateOTP(
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

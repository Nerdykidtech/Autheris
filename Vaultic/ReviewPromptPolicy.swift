import Foundation

/// The rules that decide whether Autheris may ask for an App Store review.
///
/// Pure and dependency-free, like `PrivacyShield` and `TrashBin`, so every rule
/// can be asserted without a simulator.
///
/// This decides *eligibility only*. Which moments count as having earned an ask
/// is the caller's business — see `ReviewPrompt.momentFinished`.
///
/// Two things are deliberately absent. The system's own ceiling — three prompts
/// per user per 365 days — is Apple's to enforce, not ours. And whether a prompt
/// actually appeared cannot be known at all: `AppStore.requestReview(in:)`
/// returns nothing and may drop a request silently.
enum ReviewPromptPolicy {
    /// How many codes a vault must hold before the app will ask.
    ///
    /// One code is the first thing anybody adds, and asking around then lands in
    /// the middle of onboarding.
    static let minimumCodeCount = 2

    /// On how many different days a code must have been copied before the app
    /// will ask.
    ///
    /// The code count says what is in the vault, not whether the app has been
    /// any use: someone who imports thirty codes on day one has a full vault and
    /// no experience of it. A copy is the app doing its job — getting someone
    /// signed in — and copies on several separate days mean it has kept doing it.
    static let minimumUsageDays = 3

    /// How many codes an import must add before finishing it counts as a moment
    /// worth asking after.
    ///
    /// A batch is a migration from another app, done once and with no website
    /// waiting. A single code from a link is usually a website mid-setup, waiting
    /// for the first code to be typed back — the worst time to ask.
    static let minimumImportBatch = 2

    /// Whether the app may raise the prompt on its own.
    ///
    /// - Parameters:
    ///   - codeCount: How many codes the vault holds right now.
    ///   - usageDays: On how many different days a code has been copied.
    ///   - currentVersion: The running `CFBundleShortVersionString`.
    ///   - lastRequestedVersion: The version the app last asked in, if it has.
    static func shouldRequest(codeCount: Int,
                              usageDays: Int,
                              currentVersion: String,
                              lastRequestedVersion: String?) -> Bool {
        // A build with no version string has nothing to record an ask against, so
        // "once per version" cannot be honoured. Don't ask rather than ask at
        // every moment that would otherwise earn one.
        guard !currentVersion.isEmpty else { return false }

        guard codeCount >= minimumCodeCount else { return false }
        guard usageDays >= minimumUsageDays else { return false }

        return lastRequestedVersion != currentVersion
    }

    /// Whether finishing an import that added `added` codes earns an ask.
    static func importEarnsAsk(added: Int) -> Bool {
        added >= minimumImportBatch
    }

    /// The usage-day count after a copy on `today`.
    ///
    /// Only the first copy of a day counts. Any day other than the last one
    /// recorded counts as new — including an earlier one, so a clock that was
    /// once set far ahead cannot stop the count for good. The count is read back
    /// from `UserDefaults`, so it is clamped rather than trusted not to overflow.
    ///
    /// - Parameters:
    ///   - today: The day of the copy, as a day number.
    ///   - lastDay: The day of the last copy that counted, if there was one.
    ///   - usageDays: The count so far.
    static func usageDays(afterCopyOn today: Int, lastDay: Int?, usageDays: Int) -> Int {
        let current = max(0, usageDays)
        guard today != lastDay else { return current }
        let (next, overflow) = current.addingReportingOverflow(1)
        return overflow ? Int.max : next
    }
}

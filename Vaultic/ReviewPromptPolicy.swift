import Foundation

/// The rules that decide whether Autheris may ask for an App Store review.
///
/// Pure and dependency-free, like `PrivacyShield` and `TrashBin`, so every rule
/// can be asserted without a simulator.
///
/// This decides *eligibility only*. Which moment counts as having earned an ask is
/// the caller's business — today that is a change made in Settings, raised by
/// `ReviewPrompt`.
///
/// Two things are deliberately absent. The system's own ceiling — three prompts
/// per user per 365 days — is Apple's to enforce, not ours. And whether a prompt
/// actually appeared cannot be known at all: `AppStore.requestReview(in:)`
/// returns nothing and may drop a request silently.
enum ReviewPromptPolicy {
    /// How many codes a vault must hold before the app will ask.
    ///
    /// One code is the first thing anybody adds, and asking around then lands in
    /// the middle of onboarding. Two means they came back and used the app, which
    /// is the moment worth asking about — and asking on launch, before they have
    /// done anything, is the pattern Apple's guidance warns against.
    static let minimumCodeCount = 2

    /// Whether the app may raise the prompt on its own.
    ///
    /// - Parameters:
    ///   - codeCount: How many codes the vault holds right now.
    ///   - currentVersion: The running `CFBundleShortVersionString`.
    ///   - lastRequestedVersion: The version the app last asked in, if it has.
    static func shouldRequest(codeCount: Int,
                             currentVersion: String,
                             lastRequestedVersion: String?) -> Bool {
        // A build with no version string has nothing to record an ask against, so
        // "once per version" cannot be honoured. Don't ask rather than ask every
        // time a setting changes.
        guard !currentVersion.isEmpty else { return false }

        guard codeCount >= minimumCodeCount else { return false }

        return lastRequestedVersion != currentVersion
    }
}

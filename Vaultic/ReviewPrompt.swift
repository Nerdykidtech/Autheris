import Foundation

/// Raising the system's App Store review prompt.
///
/// `PlatformReview` owns the platform-specific call and reports nothing back —
/// the system decides whether anything is shown, and caps it at three prompts per
/// user per 365 days. This layer owns the one rule the app controls: asking at
/// most once per version.
///
/// The record lives in `UserDefaults`, not in the Keychain mirror that
/// `PreferencesStore` keeps. It is bookkeeping about what we have already asked,
/// rather than a preference the user set, and it should not survive a reinstall
/// the way their privacy settings deliberately do.
@MainActor
enum ReviewPrompt {
    private static let lastRequestedVersionKey = "lastReviewRequestVersion"

    /// How long to wait before showing anything, so a prompt never lands on top of
    /// the animation for whatever the user just did.
    private static let settleDelay = Duration.seconds(1)

    /// The version being run, which is what an ask is recorded against.
    private static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    /// Ask, if a change in Settings has earned it.
    ///
    /// A Settings change is the only thing that raises this. It is deliberate and
    /// engaged without being in the middle of the task the app exists for —
    /// whereas asking off the back of adding or copying a code interrupts the
    /// exact thing the user opened the app to do.
    static func settingsChanged(codeCount: Int) {
        let lastRequested = UserDefaults.standard.string(forKey: lastRequestedVersionKey)

        guard ReviewPromptPolicy.shouldRequest(codeCount: codeCount,
                                              currentVersion: currentVersion,
                                              lastRequestedVersion: lastRequested) else { return }

        // Spend the ask now rather than when the prompt appears: `requestReview`
        // reports nothing back, so a second ask in the same version is the failure
        // worth preventing.
        UserDefaults.standard.set(currentVersion, forKey: lastRequestedVersionKey)

        // Then let the screen settle, so the prompt does not land on the animation
        // of the toggle the user just flipped.
        Task { @MainActor in
            try? await Task.sleep(for: settleDelay)
            PlatformReview.request()
        }
    }

    /// Where a review can be written, for the Settings row.
    ///
    /// Apple's documented way to give people a "rate this app" control: the
    /// product page with `action=write-review`, which opens the App Store app on
    /// the review form.
    ///
    /// This is deliberately *not* `AppStore.requestReview(in:)`. That API is for
    /// asking opportunistically — Apple's own note is that it "may not present an
    /// alert", so it must not be called from a button tap — and it does nothing
    /// at all in TestFlight builds, which is a poor showing for a control the
    /// user pressed on purpose. The link works everywhere.
    static var writeReviewURL: URL? {
        URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review")
    }

    /// Autheris's App Store app ID, which the write-review link is built from.
    private static let appStoreID = "6760686327"
}

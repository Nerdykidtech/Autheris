import Foundation

/// Raising the system's App Store review prompt.
///
/// `PlatformReview` owns the platform-specific call and reports nothing back —
/// the system decides whether anything is shown, and caps it at three prompts per
/// user per 365 days. This layer owns what the app controls: keeping the count
/// of days a code was copied, and asking at most once per version.
///
/// The record lives in `UserDefaults`, not in the Keychain mirror that
/// `PreferencesStore` keeps. It is bookkeeping about what we have already asked,
/// rather than a preference the user set, and it should not survive a reinstall
/// the way their privacy settings deliberately do.
@MainActor
enum ReviewPrompt {
    private static let lastRequestedVersionKey = "lastReviewRequestVersion"
    private static let usageDaysKey = "reviewUsageDays"
    private static let lastUsageDayKey = "reviewLastUsageDay"

    /// How long to wait before showing anything, so a prompt never lands on top of
    /// the animation for whatever the user just did.
    private static let settleDelay = Duration.seconds(1)

    /// The version being run, which is what an ask is recorded against.
    private static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    /// Count a copied code toward the days the app has been used.
    ///
    /// Called on every copy; only the first one of a day changes anything. See
    /// `ReviewPromptPolicy.usageDays(afterCopyOn:lastDay:usageDays:)`.
    static func codeCopied(now: Date = .now) {
        let defaults = UserDefaults.standard
        let today = dayNumber(of: now)
        let lastDay = defaults.object(forKey: lastUsageDayKey) as? Int
        guard today != lastDay else { return }

        let days = ReviewPromptPolicy.usageDays(afterCopyOn: today,
                                                lastDay: lastDay,
                                                usageDays: defaults.integer(forKey: usageDaysKey))
        defaults.set(days, forKey: usageDaysKey)
        defaults.set(today, forKey: lastUsageDayKey)
    }

    /// Ask, if the user has just finished something that earns it.
    ///
    /// The moments that call this are housekeeping, done with no website waiting
    /// for a code: changing a setting, saving an edit to a token, finishing a
    /// batch import, creating a backup, and turning on iCloud sync. Opening the
    /// app, copying a code and adding one never do — each is someone in the middle
    /// of signing in, and adding one usually has a website waiting for its first
    /// code. Reordering doesn't either: it is a run of drags, and asking after the
    /// first would interrupt the rest.
    ///
    /// Callers that end in a sheet or alert call this as it is dismissed, so the
    /// prompt doesn't arrive on top of their own result.
    static func momentFinished(codeCount: Int) {
        let defaults = UserDefaults.standard
        let lastRequested = defaults.string(forKey: lastRequestedVersionKey)

        guard ReviewPromptPolicy.shouldRequest(codeCount: codeCount,
                                               usageDays: defaults.integer(forKey: usageDaysKey),
                                               currentVersion: currentVersion,
                                               lastRequestedVersion: lastRequested) else { return }

        // Spend the ask now rather than when the prompt appears: `requestReview`
        // reports nothing back, so a second ask in the same version is the failure
        // worth preventing.
        defaults.set(currentVersion, forKey: lastRequestedVersionKey)

        // Then let the screen settle, so the prompt does not land on the animation
        // of whatever the user just finished.
        Task { @MainActor in
            try? await Task.sleep(for: settleDelay)
            PlatformReview.request()
        }
    }

    /// `date`'s day in the user's calendar, as a number that changes once a day.
    ///
    /// In the calendar's current time zone, so a copy either side of a change
    /// of time zone can land on different days and count twice. Left so: the bar
    /// is a few days of use, and one extra day is not worth tracking zones for.
    private static func dayNumber(of date: Date) -> Int {
        let calendar = Calendar.current
        let reference = calendar.startOfDay(for: Date(timeIntervalSinceReferenceDate: 0))
        return calendar.dateComponents([.day], from: reference,
                                       to: calendar.startOfDay(for: date)).day ?? 0
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

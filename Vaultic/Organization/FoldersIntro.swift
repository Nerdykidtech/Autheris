import Foundation

/// When to introduce Folders to someone who already used Autheris before 3.2.
///
/// Shown once, after updating, to a user who had finished onboarding and has not
/// turned folders on. A new install never sees it: finishing onboarding marks it seen
/// (see `OnboardingChoices.complete`), since the welcome is their introduction.
nonisolated enum FoldersIntro {
    /// The `@AppStorage` key that records the sheet was seen, or skipped.
    static let seenKey = "foldersIntroSeen"

    static func shouldShow(hasCompletedOnboarding: Bool, introSeen: Bool, foldersEnabled: Bool) -> Bool {
        hasCompletedOnboarding && !introSeen && !foldersEnabled
    }
}

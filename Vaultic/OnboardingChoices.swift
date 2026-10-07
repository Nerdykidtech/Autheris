import Foundation

/// What a new install decides during onboarding, and the one place it is saved.
///
/// Service logos are the reason this exists. Looking a logo up sends the
/// service's name to logo.dev, so a new install starts with it off and the
/// privacy page asks. Everyone who installed before 3.1 had it on, and never
/// wrote the key, so a missing key still reads as on
/// (`AppPreferences.defaults.fetchIssuerLogos`). The two are told apart by
/// onboarding: a new install finishes it and writes its answer here, while an
/// update, or a reinstall whose preferences come back from the Keychain, never
/// sees it.
///
/// The other privacy switches are bound straight to their `@AppStorage` keys on
/// the privacy page, since their defaults don't change.
struct OnboardingChoices: Equatable {
    /// Off for a new install; see the type's comment.
    static let newInstallFetchesLogos = false

    var fetchIssuerLogos = OnboardingChoices.newInstallFetchesLogos

    /// Saves the choices and marks onboarding done, in that order: the list
    /// appears as soon as `hasCompletedOnboarding` is set, and its icons read
    /// the logo key the moment they're drawn.
    func complete(in defaults: UserDefaults = .standard) {
        defaults.set(fetchIssuerLogos, forKey: AppPreferences.fetchIssuerLogosKey)
        defaults.set(true, forKey: "hasCompletedOnboarding")
    }
}

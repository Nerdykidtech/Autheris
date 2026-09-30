import Foundation

/// The preferences that get mirrored into the Keychain so they survive an app
/// reinstall.
///
/// Kept in its own dependency-free file for two reasons: the decoding rule below
/// is compatibility-critical and can only be tested for real if the type has no
/// UIKit/SwiftUI dependencies, and the shape then lives in exactly one place
/// while `PreferencesStore` stays about the Keychain plumbing.
struct AppPreferences: Codable, Equatable {
    var hasCompletedOnboarding: Bool
    var enablePrivacyBlur: Bool
    var hideCodesInAppSwitcher: Bool
    var hideCodesWhenScreenCaptured: Bool
    var accentTheme: String
    var enableAppLock: Bool
    var isICloudSyncEnabled: Bool
    var fetchIssuerLogos: Bool

    /// The `@AppStorage` key the Settings switch and the logo lookup share, so the
    /// one that writes and the one that reads cannot drift apart.
    ///
    /// `nonisolated` so it can be used in an `@AppStorage` attribute, which is
    /// evaluated outside an actor context — the same reason
    /// `OTPDataStore.syncEnabledKey` is.
    nonisolated static let fetchIssuerLogosKey = "fetchIssuerLogos"

    init(hasCompletedOnboarding: Bool,
         enablePrivacyBlur: Bool,
         hideCodesInAppSwitcher: Bool,
         hideCodesWhenScreenCaptured: Bool,
         accentTheme: String,
         enableAppLock: Bool,
         isICloudSyncEnabled: Bool,
         fetchIssuerLogos: Bool) {
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.enablePrivacyBlur = enablePrivacyBlur
        self.hideCodesInAppSwitcher = hideCodesInAppSwitcher
        self.hideCodesWhenScreenCaptured = hideCodesWhenScreenCaptured
        self.accentTheme = accentTheme
        self.enableAppLock = enableAppLock
        self.isICloudSyncEnabled = isICloudSyncEnabled
        self.fetchIssuerLogos = fetchIssuerLogos
    }

    enum CodingKeys: String, CodingKey {
        case hasCompletedOnboarding
        case enablePrivacyBlur
        case hideCodesInAppSwitcher
        case hideCodesWhenScreenCaptured
        case accentTheme
        case enableAppLock
        case isICloudSyncEnabled
        case fetchIssuerLogos
    }

    /// Every key is optional on the way in.
    ///
    /// `PreferencesStore.restoreIntoUserDefaults` decodes this blob with `try?`
    /// and abandons the whole thing if any single key is missing. A preference
    /// added in a later release would therefore silently reset *every other*
    /// preference to its default for a user restoring after a reinstall, so a
    /// missing key has to fall back to that preference's own default instead of
    /// failing the decode.
    ///
    /// The defaults here must match the `@AppStorage` defaults in the views and
    /// the `UserDefaults.bool(forKey:)` reads in `AppLockManager` / `OTPDataStore`.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
        enablePrivacyBlur = try container.decodeIfPresent(Bool.self, forKey: .enablePrivacyBlur) ?? true
        hideCodesInAppSwitcher = try container.decodeIfPresent(Bool.self, forKey: .hideCodesInAppSwitcher) ?? true
        hideCodesWhenScreenCaptured = try container.decodeIfPresent(Bool.self, forKey: .hideCodesWhenScreenCaptured) ?? true
        accentTheme = try container.decodeIfPresent(String.self, forKey: .accentTheme) ?? ""
        enableAppLock = try container.decodeIfPresent(Bool.self, forKey: .enableAppLock) ?? false
        isICloudSyncEnabled = try container.decodeIfPresent(Bool.self, forKey: .isICloudSyncEnabled) ?? false
        // On by default, because that is what the app has always done and what most
        // people expect an authenticator's list to look like. The switch is there for
        // the ones who would rather the lookup never happened; see `SettingsView`.
        fetchIssuerLogos = try container.decodeIfPresent(Bool.self, forKey: .fetchIssuerLogos) ?? true
    }
}

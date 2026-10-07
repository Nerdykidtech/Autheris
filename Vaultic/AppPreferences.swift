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
    var sendCodesToWatch: Bool
    /// Which release's rules wrote this blob; see `currentSchemaVersion`.
    var schemaVersion: Int

    /// Bumped when a blob written by an older release has to be treated
    /// differently on restore.
    ///
    /// 2: releases before 2.9 mirrored the three privacy switches as `false`
    /// for anyone who had never touched them, because `UserDefaults.bool(forKey:)`
    /// reads a missing key as `false` rather than as the switch's `true` default.
    /// A version-1 blob's `false` there can't be trusted, so restoring one turns
    /// them back on, once; see `PreferencesStore.restoreIntoUserDefaults`.
    static let currentSchemaVersion = 2

    /// What each preference is before the user has touched it. The `@AppStorage`
    /// defaults in the views must match these.
    ///
    /// `fetchIssuerLogos` is the one exception to "before the user has touched
    /// it": `true` is what an install from before 3.1 reads, because it never
    /// wrote the key. A new install writes `false` when it finishes onboarding
    /// (`OnboardingChoices`), so it never falls back to this.
    static let defaults = AppPreferences(hasCompletedOnboarding: false,
                                         enablePrivacyBlur: true,
                                         hideCodesInAppSwitcher: true,
                                         hideCodesWhenScreenCaptured: true,
                                         accentTheme: "",
                                         enableAppLock: false,
                                         isICloudSyncEnabled: false,
                                         fetchIssuerLogos: AppPreferences.fetchIssuerLogosDefault,
                                         sendCodesToWatch: AppPreferences.sendCodesToWatchDefault)

    /// The `@AppStorage` key the Settings switch and the logo lookup share, so the
    /// one that writes and the one that reads cannot drift apart.
    ///
    /// `nonisolated` so it can be used in an `@AppStorage` attribute, which is
    /// evaluated outside an actor context — the same reason
    /// `OTPDataStore.syncEnabledKey` is.
    nonisolated static let fetchIssuerLogosKey = "fetchIssuerLogos"

    /// What the logo switch reads as before anything has written it: on,
    /// because every install before 3.1 looked logos up and never wrote the
    /// key. A new install writes its own answer in onboarding
    /// (`OnboardingChoices`). The one place this is spelled, for every reader
    /// of the key — `LogoCacheManager`, both views' `@AppStorage`, and the
    /// Keychain mirror. `nonisolated` for the same reason as the key.
    nonisolated static let fetchIssuerLogosDefault = true

    /// Whether the iPhone sends codes to the Apple Watch app. Read by
    /// `WatchConnectivityTokenRelay`; written by Settings and onboarding.
    nonisolated static let sendCodesToWatchKey = "sendCodesToWatch"

    /// On: before 3.1 there was no switch, and every watch with the app
    /// installed received codes. Keeping that for an unwritten key means an
    /// update doesn't empty anyone's watch.
    nonisolated static let sendCodesToWatchDefault = true

    init(hasCompletedOnboarding: Bool,
         enablePrivacyBlur: Bool,
         hideCodesInAppSwitcher: Bool,
         hideCodesWhenScreenCaptured: Bool,
         accentTheme: String,
         enableAppLock: Bool,
         isICloudSyncEnabled: Bool,
         fetchIssuerLogos: Bool,
         sendCodesToWatch: Bool = AppPreferences.sendCodesToWatchDefault,
         schemaVersion: Int = AppPreferences.currentSchemaVersion) {
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.enablePrivacyBlur = enablePrivacyBlur
        self.hideCodesInAppSwitcher = hideCodesInAppSwitcher
        self.hideCodesWhenScreenCaptured = hideCodesWhenScreenCaptured
        self.accentTheme = accentTheme
        self.enableAppLock = enableAppLock
        self.isICloudSyncEnabled = isICloudSyncEnabled
        self.fetchIssuerLogos = fetchIssuerLogos
        self.sendCodesToWatch = sendCodesToWatch
        self.schemaVersion = schemaVersion
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
        case sendCodesToWatch
        case schemaVersion
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
    /// The fallbacks are `defaults`, which must also match the
    /// `UserDefaults.bool(forKey:)` reads in `AppLockManager` / `OTPDataStore`.
    /// A blob with no `schemaVersion` was written before there was one: version 1.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self.defaults
        hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? defaults.hasCompletedOnboarding
        enablePrivacyBlur = try container.decodeIfPresent(Bool.self, forKey: .enablePrivacyBlur) ?? defaults.enablePrivacyBlur
        hideCodesInAppSwitcher = try container.decodeIfPresent(Bool.self, forKey: .hideCodesInAppSwitcher) ?? defaults.hideCodesInAppSwitcher
        hideCodesWhenScreenCaptured = try container.decodeIfPresent(Bool.self, forKey: .hideCodesWhenScreenCaptured) ?? defaults.hideCodesWhenScreenCaptured
        accentTheme = try container.decodeIfPresent(String.self, forKey: .accentTheme) ?? defaults.accentTheme
        enableAppLock = try container.decodeIfPresent(Bool.self, forKey: .enableAppLock) ?? defaults.enableAppLock
        isICloudSyncEnabled = try container.decodeIfPresent(Bool.self, forKey: .isICloudSyncEnabled) ?? defaults.isICloudSyncEnabled
        // A missing key reads as on: a blob without it was written by a release
        // that always looked icons up. A new install is asked during onboarding
        // instead, and starts with it off; see `OnboardingChoices`.
        fetchIssuerLogos = try container.decodeIfPresent(Bool.self, forKey: .fetchIssuerLogos) ?? defaults.fetchIssuerLogos
        sendCodesToWatch = try container.decodeIfPresent(Bool.self, forKey: .sendCodesToWatch) ?? defaults.sendCodesToWatch
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
    }

}

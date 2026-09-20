import Foundation

/// Preferences that should survive an app reinstall.
///
/// UserDefaults is wiped when the app is deleted, but the Keychain is not, so
/// we mirror these values into a single Keychain item and restore them into
/// UserDefaults on launch. The live views keep using `@AppStorage`, so
/// reactivity is unchanged.
private struct AppPreferences: Codable {
    var hasCompletedOnboarding: Bool
    var enablePrivacyBlur: Bool
    var hideCodesInAppSwitcher: Bool
    var accentTheme: String
    var enableAppLock: Bool
    var isICloudSyncEnabled: Bool
}

enum PreferencesStore {
    private static let account = "appPreferences"

    static func persist() {
        let defaults = UserDefaults.standard
        let prefs = AppPreferences(
            hasCompletedOnboarding: defaults.bool(forKey: "hasCompletedOnboarding"),
            enablePrivacyBlur: defaults.bool(forKey: "enablePrivacyBlur"),
            hideCodesInAppSwitcher: defaults.bool(forKey: "hideCodesInAppSwitcher"),
            accentTheme: defaults.string(forKey: "accentTheme") ?? "",
            enableAppLock: defaults.bool(forKey: AppLockEnabledKey),
            isICloudSyncEnabled: defaults.bool(forKey: OTPDataStore.syncEnabledKey)
        )

        if let data = try? JSONEncoder().encode(prefs) {
            _ = KeychainStore.save(data, account: account)
        }
    }

    /// Copies the Keychain-backed preferences back into UserDefaults. Call this
    /// before anything reads `@AppStorage` / UserDefaults-backed state.
    static func restoreIntoUserDefaults() {
        guard let data = KeychainStore.load(account: account),
              let prefs = try? JSONDecoder().decode(AppPreferences.self, from: data) else {
            return
        }

        let defaults = UserDefaults.standard
        defaults.set(prefs.hasCompletedOnboarding, forKey: "hasCompletedOnboarding")
        defaults.set(prefs.enablePrivacyBlur, forKey: "enablePrivacyBlur")
        defaults.set(prefs.hideCodesInAppSwitcher, forKey: "hideCodesInAppSwitcher")
        defaults.set(prefs.accentTheme, forKey: "accentTheme")
        defaults.set(prefs.enableAppLock, forKey: AppLockEnabledKey)
        defaults.set(prefs.isICloudSyncEnabled, forKey: OTPDataStore.syncEnabledKey)
    }
}

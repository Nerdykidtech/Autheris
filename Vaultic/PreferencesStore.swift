import Foundation

/// Preferences that should survive an app reinstall.
///
/// UserDefaults is wiped when the app is deleted, but the Keychain is not, so
/// we mirror these values into a single Keychain item and restore them into
/// UserDefaults on launch. The live views keep using `@AppStorage`, so
/// reactivity is unchanged.
///
/// The mirrored shape — and the rule for decoding a blob written by an older
/// release — lives in `AppPreferences.swift`.

enum PreferencesStore {
    private static let account = "appPreferences"

    /// The `UserDefaults` observer installed by `startMirroringChanges()`.
    private static var mirrorObserver: NSObjectProtocol?

    /// Persists to the Keychain on every `UserDefaults` change, from now until the
    /// app quits.
    ///
    /// Safe to call more than once — every window's root view calls it as it
    /// appears — because only the first call installs the observer. One observer
    /// per window would write the Keychain once per open window for every change.
    /// It is called from the view rather than earlier so that
    /// `restoreIntoUserDefaults()` has already run: its writes would otherwise
    /// each be mirrored straight back, half-restored.
    static func startMirroringChanges() {
        guard mirrorObserver == nil else { return }
        mirrorObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            persist()
        }
    }

    static func persist() {
        let defaults = UserDefaults.standard
        let prefs = AppPreferences(
            hasCompletedOnboarding: defaults.bool(forKey: "hasCompletedOnboarding"),
            enablePrivacyBlur: defaults.bool(forKey: "enablePrivacyBlur"),
            hideCodesInAppSwitcher: defaults.bool(forKey: "hideCodesInAppSwitcher"),
            hideCodesWhenScreenCaptured: defaults.bool(forKey: "hideCodesWhenScreenCaptured"),
            accentTheme: defaults.string(forKey: "accentTheme") ?? "",
            enableAppLock: defaults.bool(forKey: AppLockEnabledKey),
            isICloudSyncEnabled: defaults.bool(forKey: OTPDataStore.syncEnabledKey),
            fetchIssuerLogos: defaults.object(forKey: AppPreferences.fetchIssuerLogosKey) as? Bool ?? true
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
        defaults.set(prefs.hideCodesWhenScreenCaptured, forKey: "hideCodesWhenScreenCaptured")
        defaults.set(prefs.accentTheme, forKey: "accentTheme")
        defaults.set(prefs.enableAppLock, forKey: AppLockEnabledKey)
        defaults.set(prefs.isICloudSyncEnabled, forKey: OTPDataStore.syncEnabledKey)
        defaults.set(prefs.fetchIssuerLogos, forKey: AppPreferences.fetchIssuerLogosKey)
    }
}

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

    /// Whether this process has read the Keychain copy — or found there is none.
    ///
    /// Until it has, `persist()` writes nothing. A launch while the device is
    /// locked can't read it, and saving `UserDefaults` over it then would skip
    /// whatever the read was for: the one-time privacy repair, most of all.
    private(set) static var hasReadStoredPreferences = false

    #if DEBUG
    /// Puts the flag back to "not read", as a launch on a locked device leaves it.
    static func forgetStoredPreferencesWereRead() {
        hasReadStoredPreferences = false
    }
    #endif

    /// Persists to the Keychain on every `UserDefaults` change, from now until the
    /// app quits.
    ///
    /// Safe to call more than once — every window's root view calls it as it
    /// appears — because only the first call installs the observer. One observer
    /// per window would write the Keychain once per open window for every change.
    /// It is called from the view rather than earlier so that
    /// `restoreIntoUserDefaults()` has already run: its writes would otherwise
    /// each be mirrored straight back, half-restored.
    /// Whether `startMirroringChanges()` has installed its observer.
    static var isMirroringChanges: Bool { mirrorObserver != nil }

    /// Removes the observer `startMirroringChanges()` installed. For tests that
    /// write the Keychain copy themselves and must not have it saved over
    /// mid-test; the app never stops mirroring.
    static func stopMirroringChanges() {
        guard let mirrorObserver else { return }
        NotificationCenter.default.removeObserver(mirrorObserver)
        self.mirrorObserver = nil
    }

    static func startMirroringChanges() {
        guard mirrorObserver == nil else { return }
        mirrorObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { persist() }
        }
    }

    static func persist() {
        guard hasReadStoredPreferences else { return }
        let prefs = snapshot(of: .standard)

        if let data = try? JSONEncoder().encode(prefs) {
            _ = KeychainStore.save(data, account: account)
        }
    }

    /// The preferences as `defaults` currently holds them.
    ///
    /// A key that has never been written reads as that preference's default.
    /// `UserDefaults.bool(forKey:)` would read it as `false`, which for the three
    /// privacy switches — `true` by default, and never written by `@AppStorage`
    /// until the user flips them — mirrored "off" into the Keychain for anyone who
    /// had left them alone.
    static func snapshot(of defaults: UserDefaults) -> AppPreferences {
        let fallback = AppPreferences.defaults
        func bool(_ key: String, _ fallback: Bool) -> Bool {
            defaults.object(forKey: key) as? Bool ?? fallback
        }
        return AppPreferences(
            hasCompletedOnboarding: bool("hasCompletedOnboarding", fallback.hasCompletedOnboarding),
            enablePrivacyBlur: bool("enablePrivacyBlur", fallback.enablePrivacyBlur),
            hideCodesInAppSwitcher: bool("hideCodesInAppSwitcher", fallback.hideCodesInAppSwitcher),
            hideCodesWhenScreenCaptured: bool("hideCodesWhenScreenCaptured", fallback.hideCodesWhenScreenCaptured),
            accentTheme: defaults.string(forKey: "accentTheme") ?? fallback.accentTheme,
            enableAppLock: bool(AppLockEnabledKey, fallback.enableAppLock),
            isICloudSyncEnabled: bool(OTPDataStore.syncEnabledKey, fallback.isICloudSyncEnabled),
            fetchIssuerLogos: bool(AppPreferences.fetchIssuerLogosKey, fallback.fetchIssuerLogos)
        )
    }

    /// `restoreIntoUserDefaults()`, for a launch that couldn't read the Keychain:
    /// called once the device unlocks.
    static func restoreIfNotYetRead() {
        guard !hasReadStoredPreferences else { return }
        restoreIntoUserDefaults()
    }

    /// Copies the Keychain-backed preferences back into UserDefaults. Call this
    /// before anything reads `@AppStorage` / UserDefaults-backed state.
    static func restoreIntoUserDefaults() {
        let stored = KeychainStore.read(account: account)
        if case .unavailable = stored { return }
        hasReadStoredPreferences = true

        guard let data = stored.data,
              var prefs = try? JSONDecoder().decode(AppPreferences.self, from: data) else {
            return
        }

        // A blob from before 2.9 may hold `false` for the privacy switches only
        // because they were never touched; see `AppPreferences.currentSchemaVersion`.
        // Turn them back on once, and re-save so it is only once.
        let needsPrivacyRepair = prefs.schemaVersion < 2
        if needsPrivacyRepair {
            prefs.enablePrivacyBlur = true
            prefs.hideCodesInAppSwitcher = true
            prefs.hideCodesWhenScreenCaptured = true
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

        if needsPrivacyRepair {
            persist()
        }
    }
}

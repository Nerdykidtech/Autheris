import XCTest
import Security
@testable import Vaultic

/// What `PreferencesStore` mirrors into the Keychain, and what it puts back.
///
/// The three privacy switches default to on, but `@AppStorage` never writes a
/// default to `UserDefaults`. Reading them back with `bool(forKey:)` mirrored
/// them as off for everyone who had left them alone, and the next launch
/// restored that — so these start from defaults that have never been written.
@MainActor
final class PreferencesStoreTests: XCTestCase {

    private let account = "appPreferences"
    private let privacyKeys = ["enablePrivacyBlur", "hideCodesInAppSwitcher", "hideCodesWhenScreenCaptured"]
    /// Every key `restoreIntoUserDefaults()` writes, so the host app's own
    /// values can be put back afterwards.
    private var restoredKeys: [String] {
        privacyKeys + ["hasCompletedOnboarding", "accentTheme", AppLockEnabledKey,
                       OTPDataStore.syncEnabledKey, AppPreferences.fetchIssuerLogosKey]
    }
    private var savedKeychain: Data?
    private var savedDefaults: [String: Any] = [:]
    private var suiteName: String!
    private var emptyDefaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        savedKeychain = KeychainStore.load(account: account)
        for key in restoredKeys {
            savedDefaults[key] = UserDefaults.standard.object(forKey: key)
        }
        suiteName = "PreferencesStoreTests.\(UUID().uuidString)"
        emptyDefaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        if let savedKeychain {
            _ = KeychainStore.save(savedKeychain, account: account)
        } else {
            var query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "com.eddingtontech.autheris",
                kSecAttrAccount as String: account
            ]
            #if os(macOS)
            query[kSecUseDataProtectionKeychain as String] = true
            #endif
            SecItemDelete(query as CFDictionary)
        }
        for key in restoredKeys {
            UserDefaults.standard.set(savedDefaults[key], forKey: key)
        }
        emptyDefaults.removePersistentDomain(forName: suiteName)
        try await super.tearDown()
    }

    private func storedPreferences() throws -> AppPreferences {
        let data = try XCTUnwrap(KeychainStore.load(account: account))
        return try JSONDecoder().decode(AppPreferences.self, from: data)
    }

    // MARK: - Mirroring

    func testSnapshotOfDefaultsNobodyHasWrittenIsEveryDefault() {
        XCTAssertEqual(PreferencesStore.snapshot(of: emptyDefaults), AppPreferences.defaults)
    }

    func testSnapshotKeepsASwitchTheUserTurnedOff() {
        emptyDefaults.set(false, forKey: "hideCodesInAppSwitcher")

        let prefs = PreferencesStore.snapshot(of: emptyDefaults)

        XCTAssertFalse(prefs.hideCodesInAppSwitcher)
        XCTAssertTrue(prefs.enablePrivacyBlur)
        XCTAssertTrue(prefs.hideCodesWhenScreenCaptured)
    }

    func testPersistWritesTheCurrentSchemaVersion() throws {
        PreferencesStore.persist()

        XCTAssertEqual(try storedPreferences().schemaVersion, AppPreferences.currentSchemaVersion)
    }

    func testPersistWritesNothingBeforeTheStoredCopyHasBeenRead() throws {
        // A launch on a locked device can't read the Keychain copy. Saving over it
        // then would skip what the read was for — the privacy repair, most of all.
        let stored = Data("a blob only a successful read may replace".utf8)
        XCTAssertTrue(KeychainStore.save(stored, account: account))
        PreferencesStore.hasReadStoredPreferences = false
        defer { PreferencesStore.hasReadStoredPreferences = true }

        PreferencesStore.persist()

        XCTAssertEqual(KeychainStore.load(account: account), stored)
    }

    func testTheDeferredReadRunsTheRepairOnUnlock() throws {
        let legacy = #"{ "enablePrivacyBlur": false, "hideCodesInAppSwitcher": false, "hideCodesWhenScreenCaptured": false }"#
        XCTAssertTrue(KeychainStore.save(Data(legacy.utf8), account: account))
        PreferencesStore.hasReadStoredPreferences = false

        PreferencesStore.restoreIfNotYetRead()

        XCTAssertTrue(PreferencesStore.hasReadStoredPreferences)
        XCTAssertEqual(try storedPreferences().schemaVersion, AppPreferences.currentSchemaVersion)
        XCTAssertEqual(UserDefaults.standard.object(forKey: "hideCodesInAppSwitcher") as? Bool, true)
    }

    // MARK: - Restoring

    func testRestoringABlobFromBeforeTheFixTurnsThePrivacySwitchesBackOnOnce() throws {
        // Exactly what an earlier release mirrored for someone who never touched
        // the switches: no schema version, and all three off.
        let legacy = """
        {
          "hasCompletedOnboarding": true,
          "enablePrivacyBlur": false,
          "hideCodesInAppSwitcher": false,
          "hideCodesWhenScreenCaptured": false,
          "accentTheme": "teal",
          "enableAppLock": true,
          "isICloudSyncEnabled": false,
          "fetchIssuerLogos": false
        }
        """
        XCTAssertTrue(KeychainStore.save(Data(legacy.utf8), account: account))

        PreferencesStore.restoreIntoUserDefaults()

        for key in privacyKeys {
            XCTAssertEqual(UserDefaults.standard.object(forKey: key) as? Bool, true, key)
        }
        // Everything else is restored as stored.
        XCTAssertEqual(UserDefaults.standard.string(forKey: "accentTheme"), "teal")
        XCTAssertEqual(UserDefaults.standard.object(forKey: AppLockEnabledKey) as? Bool, true)
        XCTAssertEqual(UserDefaults.standard.object(forKey: AppPreferences.fetchIssuerLogosKey) as? Bool, false)

        // And it is re-saved, so a switch turned off from now on stays off.
        let repaired = try storedPreferences()
        XCTAssertEqual(repaired.schemaVersion, AppPreferences.currentSchemaVersion)
        XCTAssertTrue(repaired.enablePrivacyBlur)
        XCTAssertTrue(repaired.hideCodesInAppSwitcher)
        XCTAssertTrue(repaired.hideCodesWhenScreenCaptured)
    }

    func testRestoringACurrentBlobKeepsASwitchTheUserTurnedOff() throws {
        var prefs = AppPreferences.defaults
        prefs.hideCodesInAppSwitcher = false
        XCTAssertTrue(KeychainStore.save(try JSONEncoder().encode(prefs), account: account))

        PreferencesStore.restoreIntoUserDefaults()

        XCTAssertEqual(UserDefaults.standard.object(forKey: "hideCodesInAppSwitcher") as? Bool, false)
        XCTAssertEqual(UserDefaults.standard.object(forKey: "enablePrivacyBlur") as? Bool, true)
    }
}

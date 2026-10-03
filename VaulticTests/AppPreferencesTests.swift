import XCTest
@testable import Vaultic

/// `AppPreferences` is what carries settings across a reinstall, and its decode
/// path is the fragile part: `PreferencesStore.restoreIntoUserDefaults` uses
/// `try?`, so a single unrecognised key would discard every preference at once.
// The app target defaults to main-actor isolation, which makes the types under
// test main-actor isolated too.
@MainActor
final class AppPreferencesTests: XCTestCase {

    /// A blob exactly as an earlier release wrote it — no
    /// `hideCodesWhenScreenCaptured` key.
    private let blobFromBeforeCaptureProtection = """
    {
      "hasCompletedOnboarding": true,
      "enablePrivacyBlur": false,
      "hideCodesInAppSwitcher": false,
      "accentTheme": "purple",
      "enableAppLock": true,
      "isICloudSyncEnabled": true
    }
    """

    func testDecodesABlobWrittenBeforeTheNewPreferenceExisted() throws {
        let prefs = try JSONDecoder().decode(AppPreferences.self,
                                            from: Data(blobFromBeforeCaptureProtection.utf8))

        // Everything that was stored has to survive...
        XCTAssertTrue(prefs.hasCompletedOnboarding)
        XCTAssertFalse(prefs.enablePrivacyBlur)
        XCTAssertFalse(prefs.hideCodesInAppSwitcher)
        XCTAssertEqual(prefs.accentTheme, "purple")
        XCTAssertTrue(prefs.enableAppLock)
        XCTAssertTrue(prefs.isICloudSyncEnabled)
        // ...and the key that did not exist yet falls back to its secure default
        // instead of failing the decode and taking the others down with it.
        XCTAssertTrue(prefs.hideCodesWhenScreenCaptured)
        // The issuer-logo switch is newer still, and its default is the *other*
        // direction: the app has always looked icons up, so a blob written before the
        // switch existed must not read as "off" for someone restoring after a
        // reinstall.
        XCTAssertTrue(prefs.fetchIssuerLogos)
    }

    func testDecodesAnEmptyBlobToEveryDefault() throws {
        let prefs = try JSONDecoder().decode(AppPreferences.self, from: Data("{}".utf8))

        XCTAssertEqual(prefs, AppPreferences(hasCompletedOnboarding: false,
                                             enablePrivacyBlur: true,
                                             hideCodesInAppSwitcher: true,
                                             hideCodesWhenScreenCaptured: true,
                                             accentTheme: "",
                                             enableAppLock: false,
                                             isICloudSyncEnabled: false,
                                             fetchIssuerLogos: true,
                                             schemaVersion: 1))
    }

    func testRoundTripPreservesEveryPreference() throws {
        let original = AppPreferences(hasCompletedOnboarding: true,
                                      enablePrivacyBlur: false,
                                      hideCodesInAppSwitcher: false,
                                      hideCodesWhenScreenCaptured: false,
                                      accentTheme: "teal",
                                      enableAppLock: true,
                                      isICloudSyncEnabled: true,
                                      fetchIssuerLogos: false)

        let decoded = try JSONDecoder().decode(AppPreferences.self,
                                               from: JSONEncoder().encode(original))

        XCTAssertEqual(decoded, original)
    }

    func testUnknownFutureKeysAreIgnoredRatherThanFatal() throws {
        // A newer build can write keys this one has never heard of; decoding must
        // not become fatal in that direction either.
        let future = """
        { "hasCompletedOnboarding": true, "someFuturePreference": 42 }
        """

        let prefs = try JSONDecoder().decode(AppPreferences.self, from: Data(future.utf8))

        XCTAssertTrue(prefs.hasCompletedOnboarding)
        XCTAssertTrue(prefs.hideCodesWhenScreenCaptured)
    }
}

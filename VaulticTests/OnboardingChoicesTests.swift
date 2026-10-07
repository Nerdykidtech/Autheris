import XCTest
@testable import Vaultic

/// Service logos are off for a new install and on for everyone who already had
/// the app. Onboarding is what tells the two apart: a new install finishes it
/// and writes its answer, while an update never sees it and keeps reading a
/// missing key as on.
@MainActor
final class OnboardingChoicesTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "OnboardingChoicesTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testANewInstallStartsWithServiceLogosOff() {
        XCTAssertFalse(OnboardingChoices().fetchIssuerLogos)
    }

    func testFinishingOnboardingWithoutTouchingTheSwitchSavesLogosOff() {
        OnboardingChoices().complete(in: defaults)

        XCTAssertEqual(defaults.object(forKey: AppPreferences.fetchIssuerLogosKey) as? Bool, false)
        XCTAssertTrue(defaults.bool(forKey: "hasCompletedOnboarding"))
        XCTAssertFalse(PreferencesStore.snapshot(of: defaults).fetchIssuerLogos)
    }

    func testFinishingOnboardingWithTheSwitchOnSavesLogosOn() {
        var choices = OnboardingChoices()
        choices.fetchIssuerLogos = true
        choices.complete(in: defaults)

        XCTAssertEqual(defaults.object(forKey: AppPreferences.fetchIssuerLogosKey) as? Bool, true)
        XCTAssertTrue(PreferencesStore.snapshot(of: defaults).fetchIssuerLogos)
    }

    /// Someone updating from a release before 3.1 never wrote the key and never
    /// sees the new onboarding, so their logos must stay on.
    func testAnExistingInstallThatNeverWroteTheKeyKeepsLogosOn() {
        defaults.set(true, forKey: "hasCompletedOnboarding")

        XCTAssertNil(defaults.object(forKey: AppPreferences.fetchIssuerLogosKey))
        XCTAssertTrue(PreferencesStore.snapshot(of: defaults).fetchIssuerLogos)
    }
}

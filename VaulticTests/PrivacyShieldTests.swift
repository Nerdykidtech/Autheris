import XCTest
@testable import Vaultic

/// The two halves of this suite matter for different reasons.
///
/// The "unchanged" cases exist because capture monitoring was added *around*
/// existing behaviour: a device that is not being recorded has to be shielded
/// exactly as it was before, or this change is a regression.
final class PrivacyShieldTests: XCTestCase {

    private let allOn = PrivacyShield.Preferences()

    // MARK: - Pre-existing behaviour, which must not have moved

    func testInactiveAppBlursAndOverlaysExactlyAsBefore() {
        let conditions = PrivacyShield.Conditions(appIsActive: false)

        XCTAssertTrue(PrivacyShield.shouldBlur(conditions, allOn))
        XCTAssertTrue(PrivacyShield.shouldShowOverlay(conditions, allOn))
    }

    func testActiveAppIsLeftAloneWhenNothingIsBeingCaptured() {
        let conditions = PrivacyShield.Conditions(appIsActive: true)

        XCTAssertFalse(PrivacyShield.shouldBlur(conditions, allOn))
        XCTAssertFalse(PrivacyShield.shouldShowOverlay(conditions, allOn))
    }

    func testSwitcherHidingHonoursItsOwnToggle() {
        let off = PrivacyShield.Preferences(hideInAppSwitcher: false)

        XCTAssertFalse(PrivacyShield.shouldShowOverlay(.init(appIsActive: false), off))
        // The background blur is a separate preference and still applies.
        XCTAssertTrue(PrivacyShield.shouldBlur(.init(appIsActive: false), off))
    }

    func testBlurToggleIsIndependentOfTheSwitcherToggle() {
        let blurOff = PrivacyShield.Preferences(blurWhenBackgrounded: false)

        XCTAssertFalse(PrivacyShield.shouldBlur(.init(appIsActive: false), blurOff))
        XCTAssertTrue(PrivacyShield.shouldShowOverlay(.init(appIsActive: false), blurOff))
    }

    // MARK: - The case this change exists for

    func testCaptureWhileStillFrontmostIsShielded() {
        // The whole point: recording starts, the app stays active, nothing
        // resigns — and the codes must stop being visible anyway.
        let captured = PrivacyShield.Conditions(appIsActive: true, screenIsCaptured: true)

        XCTAssertTrue(PrivacyShield.shouldShowOverlay(captured, allOn))
        XCTAssertTrue(PrivacyShield.shouldBlur(captured, allOn))
    }

    func testCaptureProtectionCanBeTurnedOff() {
        let off = PrivacyShield.Preferences(hideWhenScreenCaptured: false)
        let captured = PrivacyShield.Conditions(appIsActive: true, screenIsCaptured: true)

        XCTAssertFalse(PrivacyShield.shouldShowOverlay(captured, off))
        XCTAssertFalse(PrivacyShield.shouldBlur(captured, off))
    }

    func testCaptureIsShieldedEvenWhenSwitcherHidingIsOff() {
        // Turning off app-switcher hiding must not silently disable recording
        // protection too — they are separate exposures.
        let prefs = PrivacyShield.Preferences(hideInAppSwitcher: false, hideWhenScreenCaptured: true)
        let captured = PrivacyShield.Conditions(appIsActive: true, screenIsCaptured: true)

        XCTAssertTrue(PrivacyShield.shouldShowOverlay(captured, prefs))
    }

    func testCapturedWhileBackgroundedIsCoveredWhenOnlyCaptureProtectionIsOn() {
        // A recording keeps running while the app sits in the background.
        // Honouring only the app-switcher setting here would leave the recording
        // showing a blurred-but-readable token list.
        let prefs = PrivacyShield.Preferences(hideInAppSwitcher: false, hideWhenScreenCaptured: true)
        let conditions = PrivacyShield.Conditions(appIsActive: false, screenIsCaptured: true)

        XCTAssertTrue(PrivacyShield.shouldShowOverlay(conditions, prefs))
    }

    // MARK: - Exhaustive properties

    func testOverlayAppearsExactlyWhenEitherReasonApplies() {
        for appIsActive in [true, false] {
            for captured in [true, false] {
                for hideInSwitcher in [true, false] {
                    for hideWhenCaptured in [true, false] {
                        let conditions = PrivacyShield.Conditions(appIsActive: appIsActive,
                                                                  screenIsCaptured: captured)
                        let preferences = PrivacyShield.Preferences(blurWhenBackgrounded: true,
                                                                    hideInAppSwitcher: hideInSwitcher,
                                                                    hideWhenScreenCaptured: hideWhenCaptured)
                        let expected = (!appIsActive && hideInSwitcher) || (captured && hideWhenCaptured)

                        XCTAssertEqual(
                            PrivacyShield.shouldShowOverlay(conditions, preferences), expected,
                            "active=\(appIsActive) captured=\(captured) switcher=\(hideInSwitcher) capture=\(hideWhenCaptured)"
                        )
                    }
                }
            }
        }
    }

    func testBlurNeverHappensWhenTheBlurPreferenceIsOff() {
        for appIsActive in [true, false] {
            for captured in [true, false] {
                for hideWhenCaptured in [true, false] {
                    let conditions = PrivacyShield.Conditions(appIsActive: appIsActive,
                                                              screenIsCaptured: captured)
                    let preferences = PrivacyShield.Preferences(blurWhenBackgrounded: false,
                                                                hideInAppSwitcher: true,
                                                                hideWhenScreenCaptured: hideWhenCaptured)

                    XCTAssertFalse(PrivacyShield.shouldBlur(conditions, preferences),
                                   "active=\(appIsActive) captured=\(captured) capture=\(hideWhenCaptured)")
                }
            }
        }
    }

    func testBlurReducesToTheOldRuleWhenNothingIsCaptured() {
        // Guards the exact expression this replaced: `blur && !appIsActive`.
        for appIsActive in [true, false] {
            for blurWhenBackgrounded in [true, false] {
                let conditions = PrivacyShield.Conditions(appIsActive: appIsActive,
                                                          screenIsCaptured: false)
                let preferences = PrivacyShield.Preferences(blurWhenBackgrounded: blurWhenBackgrounded,
                                                            hideInAppSwitcher: true,
                                                            hideWhenScreenCaptured: true)

                XCTAssertEqual(PrivacyShield.shouldBlur(conditions, preferences),
                               blurWhenBackgrounded && !appIsActive)
            }
        }
    }
}

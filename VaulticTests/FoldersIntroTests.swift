import XCTest
@testable import Vaultic

/// The Folders introduction is for people updating from a version without folders:
/// once, after onboarding, and never while folders are already on.
final class FoldersIntroTests: XCTestCase {

    func testAnUpdatingUserWhoHasNotSeenItIsShownIt() {
        XCTAssertTrue(FoldersIntro.shouldShow(hasCompletedOnboarding: true, introSeen: false, foldersEnabled: false))
    }

    func testItIsShownOnlyOnce() {
        XCTAssertFalse(FoldersIntro.shouldShow(hasCompletedOnboarding: true, introSeen: true, foldersEnabled: false))
    }

    func testItIsNotShownWhenFoldersAreAlreadyOn() {
        XCTAssertFalse(FoldersIntro.shouldShow(hasCompletedOnboarding: true, introSeen: false, foldersEnabled: true))
    }

    func testItIsNotShownBeforeOnboardingIsFinished() {
        XCTAssertFalse(FoldersIntro.shouldShow(hasCompletedOnboarding: false, introSeen: false, foldersEnabled: false))
    }
}

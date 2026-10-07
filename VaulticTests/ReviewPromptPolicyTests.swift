import XCTest
@testable import Vaultic

/// Guards the rules that keep the review prompt from nagging.
///
/// The system's own ceiling — three prompts per user per 365 days — is Apple's to
/// enforce and cannot be asserted here, and neither can the moment that raises the
/// prompt, which belongs to the view that reports it. What can be asserted is the
/// part this type decides: never ask before the vault is worth commenting on or
/// the app has proved useful, never ask twice in the same version, and only count
/// a batch import as a moment worth asking after.
// The app target defaults to main-actor isolation, which makes the types under
// test main-actor isolated too.
@MainActor
final class ReviewPromptPolicyTests: XCTestCase {

    private func canAsk(codeCount: Int = 5,
                        usageDays: Int = 10,
                        currentVersion: String = "2.3",
                        lastRequestedVersion: String? = nil) -> Bool {
        ReviewPromptPolicy.shouldRequest(codeCount: codeCount,
                                         usageDays: usageDays,
                                         currentVersion: currentVersion,
                                         lastRequestedVersion: lastRequestedVersion)
    }

    // MARK: - The vault must be worth commenting on

    func testDoesNotAskForTheFirstCode() {
        XCTAssertFalse(
            canAsk(codeCount: 1),
            "one code is the first thing anyone adds — asking around then is onboarding"
        )
    }

    func testDoesNotAskForAnEmptyVault() {
        XCTAssertFalse(canAsk(codeCount: 0))
    }

    func testAsksOnceTheVaultHasEnoughCodes() {
        XCTAssertTrue(canAsk(codeCount: ReviewPromptPolicy.minimumCodeCount))
    }

    /// Someone who updated with a vault already full is eligible immediately —
    /// their eligibility never depended on the code count changing.
    func testAsksForAnExistingFullVault() {
        XCTAssertTrue(canAsk(codeCount: 40))
    }

    // MARK: - The app must have been used

    /// A full vault on day one is a migration, not an opinion of the app.
    func testDoesNotAskBeforeTheAppHasBeenUsedOnEnoughDays() {
        XCTAssertFalse(canAsk(codeCount: 30,
                              usageDays: ReviewPromptPolicy.minimumUsageDays - 1))
    }

    func testDoesNotAskWhenTheAppHasNeverBeenUsed() {
        XCTAssertFalse(canAsk(codeCount: 30, usageDays: 0))
    }

    func testAsksOnceTheAppHasBeenUsedOnEnoughDays() {
        XCTAssertTrue(canAsk(usageDays: ReviewPromptPolicy.minimumUsageDays))
    }

    func testAsksAtTheLargestUsageCount() {
        XCTAssertTrue(canAsk(usageDays: Int.max))
    }

    // MARK: - Counting usage days

    func testTheFirstCopyEverCounts() {
        XCTAssertEqual(ReviewPromptPolicy.usageDays(afterCopyOn: 100, lastDay: nil, usageDays: 0), 1)
    }

    func testASecondCopyTheSameDayDoesNotCount() {
        XCTAssertEqual(ReviewPromptPolicy.usageDays(afterCopyOn: 100, lastDay: 100, usageDays: 4), 4)
    }

    func testACopyOnANewDayCounts() {
        XCTAssertEqual(ReviewPromptPolicy.usageDays(afterCopyOn: 101, lastDay: 100, usageDays: 4), 5)
    }

    /// A clock once set ahead and then corrected must not stop the count for good.
    func testACopyOnAnEarlierDayCounts() {
        XCTAssertEqual(ReviewPromptPolicy.usageDays(afterCopyOn: 90, lastDay: 100, usageDays: 4), 5)
    }

    func testTheCountDoesNotOverflow() {
        XCTAssertEqual(ReviewPromptPolicy.usageDays(afterCopyOn: 101, lastDay: 100, usageDays: Int.max),
                       Int.max)
    }

    /// The count is read back from `UserDefaults`, which could hold anything.
    func testANegativeStoredCountStartsAgainFromZero() {
        XCTAssertEqual(ReviewPromptPolicy.usageDays(afterCopyOn: 101, lastDay: 100, usageDays: -7), 1)
        XCTAssertEqual(ReviewPromptPolicy.usageDays(afterCopyOn: 101, lastDay: 100, usageDays: Int.min), 1)
    }

    // MARK: - Imports

    func testASingleImportedCodeDoesNotEarnAnAsk() {
        XCTAssertFalse(
            ReviewPromptPolicy.importEarnsAsk(added: 1),
            "one code from a link is usually a website waiting for its first code"
        )
    }

    func testAnImportThatAddedNothingDoesNotEarnAnAsk() {
        XCTAssertFalse(ReviewPromptPolicy.importEarnsAsk(added: 0))
    }

    func testABatchImportEarnsAnAsk() {
        XCTAssertTrue(ReviewPromptPolicy.importEarnsAsk(added: ReviewPromptPolicy.minimumImportBatch))
        XCTAssertTrue(ReviewPromptPolicy.importEarnsAsk(added: Int.max))
    }

    // MARK: - Once per version

    func testDoesNotAskTwiceInTheSameVersion() {
        XCTAssertFalse(
            canAsk(codeCount: 12, lastRequestedVersion: "2.3"),
            "once per version is the whole point — the system's cap is not a substitute"
        )
    }

    func testAsksAgainInANewerVersion() {
        XCTAssertTrue(canAsk(codeCount: 12,
                             currentVersion: "2.4",
                             lastRequestedVersion: "2.3"))
    }

    /// A version that only differs in build number is still the same version, so
    /// re-uploading a build must not buy a second ask.
    func testAnIdenticalVersionStringIsTreatedAsTheSameVersion() {
        XCTAssertFalse(canAsk(codeCount: 5, lastRequestedVersion: "2.3"))
    }

    func testDoesNotAskWhenTheVersionIsUnknown() {
        XCTAssertFalse(
            canAsk(codeCount: 12, currentVersion: ""),
            "with no version to record an ask against, asking would repeat on every change"
        )
    }
}

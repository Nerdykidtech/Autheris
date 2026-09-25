import XCTest
@testable import Vaultic

/// Guards the rules that keep the review prompt from nagging.
///
/// The system's own ceiling — three prompts per user per 365 days — is Apple's to
/// enforce and cannot be asserted here, and neither can the moment that raises the
/// prompt, which belongs to the view that reports it. What can be asserted is the
/// part this type decides: never ask before the vault is worth commenting on, and
/// never ask twice in the same version.
final class ReviewPromptPolicyTests: XCTestCase {

    private func canAsk(codeCount: Int = 5,
                        currentVersion: String = "2.3",
                        lastRequestedVersion: String? = nil) -> Bool {
        ReviewPromptPolicy.shouldRequest(codeCount: codeCount,
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

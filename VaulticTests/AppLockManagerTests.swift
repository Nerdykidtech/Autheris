import XCTest
import LocalAuthentication
import Security
@testable import Vaultic

/// App Lock on a device that can't authenticate its owner.
///
/// Turning App Lock on with no passcode used to work, and the lock screen then
/// had nothing to ask for: every launch stopped there for good. A fake context
/// stands in for the device, so the cases that need a passcode removed can run.
///
/// A test that makes and drops its own manager is `async` even when it awaits
/// nothing. On iOS 26, freeing a main-actor object inside a synchronous test
/// method crashes the Swift runtime (`swift_task_deinitOnExecutor` frees a
/// task-local scope it never allocated); the same release inside a task is fine.
@MainActor
final class AppLockManagerTests: XCTestCase {

    private var wasMirroring = false

    private let preferencesAccount = "appPreferences"
    private var savedPreferences: Data?
    /// Every key `PreferencesStore.restoreIntoUserDefaults()` writes. The manager
    /// runs it on init, so all of them change, not only the App Lock setting —
    /// and the simulator's own settings have to be put back afterwards.
    private let restoredKeys = ["hasCompletedOnboarding", "enablePrivacyBlur", "hideCodesInAppSwitcher",
                                "hideCodesWhenScreenCaptured", "accentTheme", AppLockEnabledKey,
                                OTPDataStore.syncEnabledKey, AppPreferences.fetchIssuerLogosKey]
    private var savedDefaults: [String: Any] = [:]

    override func setUp() async throws {
        try await super.setUp()
        // The host app mirrors every `UserDefaults` change into the same Keychain
        // item these tests write, on the main queue — so a change from one test
        // could be saved over the next test's item mid-test.
        wasMirroring = PreferencesStore.isMirroringChanges
        PreferencesStore.stopMirroringChanges()
        savedPreferences = KeychainStore.load(account: preferencesAccount)
        for key in restoredKeys {
            savedDefaults[key] = UserDefaults.standard.object(forKey: key)
        }
        // `AppLockManager.init` restores the Keychain copy before it reads the
        // setting, so the copy is what has to say App Lock is on.
        var prefs = AppPreferences.defaults
        prefs.enableAppLock = true
        prefs.hasCompletedOnboarding = true
        XCTAssertTrue(KeychainStore.save(try JSONEncoder().encode(prefs), account: preferencesAccount))
    }

    override func tearDown() async throws {
        if let savedPreferences {
            _ = KeychainStore.save(savedPreferences, account: preferencesAccount)
        } else {
            var query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "com.eddingtontech.autheris",
                kSecAttrAccount as String: preferencesAccount
            ]
            #if os(macOS)
            query[kSecUseDataProtectionKeychain as String] = true
            #endif
            SecItemDelete(query as CFDictionary)
        }
        for key in restoredKeys {
            UserDefaults.standard.set(savedDefaults[key], forKey: key)
        }
        if wasMirroring {
            PreferencesStore.startMirroringChanges()
        }
        try await super.tearDown()
    }

    private func manager(_ context: FakeAuthenticationContext) -> AppLockManager {
        AppLockManager(makeContext: { context })
    }

    // MARK: - The unlock button

    func testTheUnlockButtonNamesFaceIDWhenTheAppMayUseIt() {
        XCTAssertEqual(manager(.faceID(allowed: true)).unlockBiometry, .faceID)
    }

    func testTheUnlockButtonDoesNotPromiseFaceIDTheAppHasBeenRefused() {
        // The hardware is Face ID, but the user turned it off for Autheris: the
        // system will ask for the passcode, so the button must not say Face ID.
        XCTAssertEqual(manager(.faceID(allowed: false)).unlockBiometry, .none)
    }

    // MARK: - No passcode

    func testWithNoPasscodeTheLockScreenLetsTheOwnerInAndTurnsAppLockOff() async {
        let lock = manager(.passcodeNotSet)
        XCTAssertTrue(lock.isLocked)

        lock.authenticate()

        XCTAssertFalse(lock.isLocked, "no passcode means nothing to ask for, not a lock with no way past it")
        XCTAssertFalse(UserDefaults.standard.bool(forKey: AppLockEnabledKey),
                       "Settings must not go on showing a lock that locks nothing")
    }

    func testAppLockCannotBeTurnedOnWithoutAPasscode() {
        XCTAssertFalse(AppLockManager.canLock(context: FakeAuthenticationContext.passcodeNotSet))
        XCTAssertTrue(AppLockManager.canLock(context: FakeAuthenticationContext.succeeds))
    }

    func testReauthenticationWithNoPasscodeIsNotABarrier() async {
        UserDefaults.standard.set(true, forKey: AppLockEnabledKey)

        let allowed = await AppLockManager.reauthenticate(reason: "test",
                                                          context: FakeAuthenticationContext.passcodeNotSet)

        XCTAssertTrue(allowed)
    }

    // MARK: - Everything else stays locked

    func testAnyOtherReasonKeepsTheLockAndSaysWhy() async {
        let lock = manager(.unavailable(.biometryNotAvailable))

        lock.authenticate()

        XCTAssertTrue(lock.isLocked)
        XCTAssertNotNil(lock.errorMessage)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: AppLockEnabledKey),
                      "only a missing passcode turns App Lock off")
    }

    func testAFailedAuthenticationKeepsTheLock() async {
        UserDefaults.standard.set(true, forKey: AppLockEnabledKey)

        let allowed = await AppLockManager.reauthenticate(reason: "test",
                                                          context: FakeAuthenticationContext.refuses)

        XCTAssertFalse(allowed)
    }

    func testASuccessfulAuthenticationUnlocks() async {
        let lock = manager(.succeeds)

        lock.authenticate()
        for _ in 0..<100 where lock.isLocked { await Task.yield() }

        XCTAssertFalse(lock.isLocked)
    }
}

/// A device with or without a passcode, that accepts or refuses.
private final class FakeAuthenticationContext: DeviceOwnerAuthenticating, @unchecked Sendable {
    private let unavailableReason: LAError.Code?
    private let evaluationSucceeds: Bool
    let biometryType: LABiometryType
    /// Whether the biometrics-only policy is refused — Face ID turned off for
    /// the app, say — while the passcode still works.
    private let biometricsRefused: Bool

    private init(unavailableReason: LAError.Code?, evaluationSucceeds: Bool,
                 biometryType: LABiometryType = .none, biometricsRefused: Bool = false) {
        self.unavailableReason = unavailableReason
        self.evaluationSucceeds = evaluationSucceeds
        self.biometryType = biometryType
        self.biometricsRefused = biometricsRefused
    }

    static func faceID(allowed: Bool) -> FakeAuthenticationContext {
        FakeAuthenticationContext(unavailableReason: nil, evaluationSucceeds: true,
                                  biometryType: .faceID, biometricsRefused: !allowed)
    }

    static let passcodeNotSet = FakeAuthenticationContext(unavailableReason: .passcodeNotSet, evaluationSucceeds: false)
    static let succeeds = FakeAuthenticationContext(unavailableReason: nil, evaluationSucceeds: true)
    static let refuses = FakeAuthenticationContext(unavailableReason: nil, evaluationSucceeds: false)

    static func unavailable(_ code: LAError.Code) -> FakeAuthenticationContext {
        FakeAuthenticationContext(unavailableReason: code, evaluationSucceeds: false)
    }

    func canEvaluatePolicy(_ policy: LAPolicy, error: NSErrorPointer) -> Bool {
        if policy == .deviceOwnerAuthenticationWithBiometrics, biometricsRefused {
            error?.pointee = NSError(domain: LAErrorDomain, code: LAError.biometryNotAvailable.rawValue)
            return false
        }
        guard let unavailableReason else { return true }
        error?.pointee = NSError(domain: LAErrorDomain, code: unavailableReason.rawValue)
        return false
    }

    func evaluatePolicy(_ policy: LAPolicy,
                        localizedReason: String,
                        reply: @escaping @Sendable (Bool, (any Error)?) -> Void) {
        reply(evaluationSucceeds, evaluationSucceeds ? nil : NSError(domain: LAErrorDomain,
                                                                      code: LAError.authenticationFailed.rawValue))
    }
}

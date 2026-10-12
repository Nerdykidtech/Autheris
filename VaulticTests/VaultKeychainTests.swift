import XCTest
import LocalAuthentication
@testable import Vaultic

/// The App Lock forms of the vault's Keychain items. These tests run without a
/// passcode or biometrics, so they cover what happens when nothing has been
/// authenticated: a bound item must never be written or read as if it were. The
/// bound round trip itself needs the owner's authentication and is checked on a
/// device.
final class VaultKeychainTests: XCTestCase {
    /// Each test uses its own account, so nothing it writes can collide with the
    /// vault or with another test.
    private var account = ""

    override func setUp() {
        super.setUp()
        account = "test.vault.\(UUID().uuidString)"
    }

    override func tearDown() {
        _ = KeychainStore.delete(account: account)
        _ = KeychainStore.delete(account: account + ".bound")
        super.tearDown()
    }

    func testAProtectedWriteNeedsAnAuthenticatedContext() {
        let written = VaultKeychain.write(Data("codes".utf8), account: account, protected: true, context: nil)

        XCTAssertFalse(written)
        XCTAssertNil(KeychainStore.load(account: account), "nothing may be stored in the plain form")
    }

    func testThePlainFormIsWrittenAndReadWhileAppLockIsOff() throws {
        let stored = Data("codes".utf8)

        XCTAssertTrue(VaultKeychain.write(stored, account: account, protected: false, context: nil))

        guard case .found(let read) = VaultKeychain.read(account: account, protected: false, context: nil) else {
            return XCTFail("the plain copy should read back")
        }
        XCTAssertEqual(read, stored)
    }

    func testAProtectedReadWithoutAuthenticationWaitsRatherThanReadingEmpty() {
        // A plain copy from before the binding exists. Without authentication it must
        // read as unavailable, not as nothing, so the vault waits for the owner rather
        // than being treated as empty and overwritten.
        XCTAssertTrue(VaultKeychain.write(Data("codes".utf8), account: account, protected: false, context: nil))

        let result = VaultKeychain.read(account: account, protected: true, context: nil)

        guard case .unavailable = result else {
            return XCTFail("expected unavailable, got \(result)")
        }
    }

    func testAnEmptyVaultReadsAsNothingStored() {
        guard case .notFound = VaultKeychain.read(account: account, protected: true, context: nil) else {
            return XCTFail("with nothing stored there is nothing to wait for")
        }
    }
}

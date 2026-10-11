import Foundation
import LocalAuthentication
import Security

/// The vault's Keychain items, bound to the owner's authentication while App Lock is on.
///
/// Hiding the lock screen was all that stood between the codes and someone holding
/// an unlocked phone. With App Lock on, each vault item is stored behind
/// `SecAccessControl(.userPresence)`: the Keychain refuses to return it until an
/// `LAContext` that has authenticated the owner is handed to it. That check runs in
/// the Keychain, not in the app, so changing the app's `isLocked` no longer opens it.
///
/// With App Lock off, items are the `WhenUnlockedThisDeviceOnly` ones they have
/// always been. Reads use only the form App Lock currently selects, and `moveAll` is
/// the one way that form changes, so a copy in the other form is never read.
///
/// A bound item lives under `<account>.bound`. It can't share the plain item's
/// account: a Keychain item is keyed by class, service and account, so a bound write
/// would land on the plain item and leave it unprotected.
nonisolated enum VaultKeychain {
    /// Every item that holds vault data. The trash and the tombstones hold secrets
    /// too (the trash keeps deleted codes whole), so they are bound with the codes.
    static let codesAccount = "otpCodes"
    static let tombstonesAccount = "otpSyncTombstones"
    static let trashAccount = "otpTrash"
    static let setAsideAccount = "otpCodes.unreadable"
    static let allAccounts = [codesAccount, tombstonesAccount, trashAccount, setAsideAccount]

    /// Whether App Lock is on, which is which form the vault is kept in.
    static var appLockIsOn: Bool {
        UserDefaults.standard.bool(forKey: AppLockEnabledKey)
    }

    /// Reads the item in the form `protected` selects.
    ///
    /// A bound read passes `context` and never lets the Keychain show its own prompt.
    /// Without an authenticated context a bound item is `.unavailable`, so a launch
    /// that is still locked waits rather than reading nothing and treating the vault
    /// as empty.
    static func read(account: String, protected: Bool, context: LAContext?) -> KeychainStore.ReadResult {
        guard protected else { return KeychainStore.read(account: account) }
        switch readBound(account: account, context: context) {
        case .notFound:
            // An install from before the binding has only its plain copy. It moves
            // to the bound form once the owner has authenticated, and until then it
            // is left unread.
            guard exists(account) else { return .notFound }
            guard let context else { return .unavailable(errSecInteractionNotAllowed) }
            return migrateLegacy(account: account, context: context)
        case let other:
            return other
        }
    }

    /// Writes the item in the form `protected` selects and removes the other form.
    /// `false` when the write did not finish. The caller keeps its copy and tries
    /// again later.
    @discardableResult
    static func write(_ data: Data, account: String, protected: Bool, context: LAContext?) -> Bool {
        if protected {
            guard let context, let access = accessControl(),
                  writeBound(data, account: account, access: access, context: context) else { return false }
            // The plain copy is the readable one, so it must not outlive the bound copy.
            return KeychainStore.delete(account: account)
        }
        guard KeychainStore.save(data, account: account) else { return false }
        // Once the plain copy is written it is the one read, so a bound copy is removed
        // now. Until then it is ignored, and `moveAll` and the next bind replace it.
        return deleteBound(account: account, context: context)
    }

    /// Moves every vault item into the form `toProtected` names, reading each from the
    /// other form. Called with the authentication the switch needed. `false` when any
    /// item could not be moved, in which case the caller leaves App Lock as it was.
    static func moveAll(toProtected: Bool, context: LAContext) -> Bool {
        for account in allAccounts {
            let source: KeychainStore.ReadResult = toProtected
                ? KeychainStore.read(account: account)
                : readBound(account: account, context: context)
            switch source {
            case .notFound:
                continue
            case .unavailable:
                return false
            case .found(let data):
                guard write(data, account: account, protected: toProtected, context: context) else { return false }
            }
        }
        return true
    }

    /// Whether any vault item is bound. This doesn't read them, so it needs no
    /// authentication, and an item that does need authentication still counts.
    static func hasBoundItems() -> Bool {
        allAccounts.contains { exists(boundAccount($0)) }
    }

    // MARK: - Bound items

    private static func boundAccount(_ account: String) -> String {
        account + ".bound"
    }

    /// The context a Keychain call uses. It never prompts: the one passed in, which
    /// has already authenticated, or a fresh one that refuses to show a prompt.
    private static func noPrompt(_ context: LAContext?) -> LAContext {
        let context = context ?? LAContext()
        context.interactionNotAllowed = true
        return context
    }

    /// Face ID, Touch ID or the passcode, whichever the owner has allowed.
    private static func accessControl() -> SecAccessControl? {
        var error: Unmanaged<CFError>?
        return SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .userPresence, &error
        )
    }

    private static func readBound(account: String, context: LAContext?) -> KeychainStore.ReadResult {
        var query = KeychainStore.query(account: boundAccount(account))
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationContext as String] = noPrompt(context)

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return (result as? Data).map(KeychainStore.ReadResult.found) ?? .unavailable(errSecDecode)
        case errSecItemNotFound:
            return .notFound
        default:
            KeychainStore.report(status, during: "read", account: boundAccount(account))
            return .unavailable(status)
        }
    }

    private static func writeBound(_ data: Data, account: String, access: SecAccessControl, context: LAContext) -> Bool {
        var query = KeychainStore.query(account: boundAccount(account))
        query[kSecUseAuthenticationContext as String] = noPrompt(context)
        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }
        guard updateStatus == errSecItemNotFound else {
            KeychainStore.report(updateStatus, during: "update", account: boundAccount(account))
            return false
        }

        var add = KeychainStore.query(account: boundAccount(account))
        add[kSecValueData as String] = data
        add[kSecAttrAccessControl as String] = access
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        KeychainStore.report(addStatus, during: "add", account: boundAccount(account))
        return addStatus == errSecSuccess
    }

    private static func deleteBound(account: String, context: LAContext?) -> Bool {
        var query = KeychainStore.query(account: boundAccount(account))
        query[kSecUseAuthenticationContext as String] = noPrompt(context)
        let status = SecItemDelete(query as CFDictionary)
        KeychainStore.report(status, during: "delete", account: boundAccount(account))
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Moves a plain item that predates the binding into the bound form.
    private static func migrateLegacy(account: String, context: LAContext) -> KeychainStore.ReadResult {
        guard case .found(let data) = KeychainStore.read(account: account),
              write(data, account: account, protected: true, context: context) else {
            return .unavailable(errSecInteractionNotAllowed)
        }
        return .found(data)
    }

    /// Whether an item is stored under `account`, without reading it. One that exists
    /// but needs authentication counts.
    private static func exists(_ account: String) -> Bool {
        var query = KeychainStore.query(account: account)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationContext as String] = noPrompt(nil)
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }
}

/// The authentication that lets this session use the bound vault.
///
/// Set when the owner authenticates (unlocking, or switching App Lock), and ended
/// when App Lock locks. Keychain calls pass its context so they don't prompt again.
/// With no context, a bound item can't be read or written, and the caller waits.
@MainActor
final class VaultSession {
    static let shared = VaultSession()

    private(set) var context: LAContext?

    /// Runs when a context arrives, so a launch that was waiting on the lock can load.
    var onBegin: (() -> Void)?

    func begin(_ newContext: LAContext) {
        context?.invalidate()
        context = newContext
        onBegin?()
    }

    func end() {
        context?.invalidate()
        context = nil
    }
}

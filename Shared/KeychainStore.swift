import Foundation
import Security

/// Minimal Generic Password Keychain store.
///
/// Each value is stored under `kSecClassGenericPassword` with
/// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, so it is only readable while
/// the device is unlocked and never migrates to another device (or an iCloud
/// Keychain backup).
enum KeychainStore {
    private static let service = "com.eddingtontech.autheris"

    /// The identity of an item, shared by every operation.
    ///
    /// On iOS this is exactly `class + service + account`. macOS needs one more
    /// key, and it is the difference between the promise above being kept and not:
    /// the `kSecAttrAccessible*` constants — and with them "this device only" —
    /// only exist in the *data protection* keychain. The older file-based
    /// keychain ignores them, and an item added there with an accessibility
    /// attribute is rejected outright. Opting in explicitly is what makes the Mac
    /// store these the same way the phone does.
    private static func query(account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        #if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif

        return query
    }

    static func save(_ data: Data, account: String) -> Bool {
        let baseQuery = query(account: account)

        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        if updateStatus == errSecSuccess {
            return true
        }

        guard updateStatus == errSecItemNotFound else {
            #if DEBUG
            print("Keychain update failed with status \(updateStatus)")
            #endif
            return false
        }

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        return addStatus == errSecSuccess
    }

    /// What a read found.
    ///
    /// "Nothing stored" and "can't look right now" have to stay distinct. These
    /// items are `WhenUnlocked`, so a launch while the device is locked (a
    /// silent push, a background fetch) can't read them at all — and treating
    /// that as an empty vault means the next save writes the empty list over the
    /// real one.
    enum ReadResult {
        case found(Data)
        case notFound
        /// The item may well exist but can't be read now, usually
        /// `errSecInteractionNotAllowed` because the device is locked.
        case unavailable(OSStatus)

        /// The stored bytes, or `nil` both when there are none and when they
        /// can't be read. Only for callers that would do the same in either case.
        var data: Data? {
            if case .found(let data) = self { return data }
            return nil
        }
    }

    static func read(account: String) -> ReadResult {
        var query = query(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return (result as? Data).map(ReadResult.found) ?? .notFound
        case errSecItemNotFound:
            return .notFound
        default:
            return .unavailable(status)
        }
    }

    /// `read(account:)` for callers that don't need to tell a missing item from
    /// an unreadable one. Anything that saves back what it loaded does need to,
    /// and should use `read` instead.
    static func load(account: String) -> Data? {
        read(account: account).data
    }
}

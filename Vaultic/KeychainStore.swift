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

    static func load(account: String) -> Data? {
        var query = query(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }
}

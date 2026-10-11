import Foundation
import os
import Security

/// Minimal Generic Password Keychain store.
///
/// Each value is stored under `kSecClassGenericPassword` with
/// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, so it is only readable while
/// the device is unlocked and never migrates to another device (or an iCloud
/// Keychain backup).
enum KeychainStore {
    private static let service = "com.eddingtontech.autheris"
    private static let log = Logger(subsystem: "com.eddingtontech.autheris", category: "Keychain")

    /// Records a Keychain call that did not succeed, with the status it returned, in
    /// every build. The item's data is never logged, only the operation, the account
    /// name (which is not secret) and the status.
    ///
    /// A status the caller will simply retry is logged as information. Anything else
    /// is an error, because it means the item may not have been written or deleted.
    static func report(_ status: OSStatus, during operation: String, account: String) {
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        case errSecInteractionNotAllowed:
            // The device is locked, or the owner hasn't authenticated. The caller keeps
            // its copy and tries again when that changes.
            log.info("\(operation, privacy: .public) of \(account, privacy: .public) waiting: not accessible right now (status \(status, privacy: .public))")
        default:
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "unknown error"
            log.error("\(operation, privacy: .public) of \(account, privacy: .public) failed: \(message, privacy: .public) (status \(status, privacy: .public))")
        }
    }

    /// The identity of an item, shared by every operation.
    ///
    /// On iOS this is exactly `class + service + account`. macOS needs one more
    /// key, and it is the difference between the promise above being kept and not:
    /// the `kSecAttrAccessible*` constants — and with them "this device only" —
    /// only exist in the *data protection* keychain. The older file-based
    /// keychain ignores them, and an item added there with an accessibility
    /// attribute is rejected outright. Opting in explicitly is what makes the Mac
    /// store these the same way the phone does.
    static func query(account: String) -> [String: Any] {
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

    /// Removes the item. `true` when it is gone, including when there was none.
    @discardableResult
    static func delete(account: String) -> Bool {
        let status = SecItemDelete(query(account: account) as CFDictionary)
        report(status, during: "delete", account: account)
        return status == errSecSuccess || status == errSecItemNotFound
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
            report(updateStatus, during: "update", account: account)
            return false
        }

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        report(addStatus, during: "add", account: account)
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
            // Found, but not as data. Not "nothing stored": a caller that heard
            // that would feel free to write over it.
            return (result as? Data).map(ReadResult.found) ?? .unavailable(errSecDecode)
        case errSecItemNotFound:
            return .notFound
        default:
            report(status, during: "read", account: account)
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

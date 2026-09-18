import CloudKit
import Foundation

/// Syncs tokens through the user's **private** CloudKit database.
///
/// ### Where the secrets live
/// `label`, `account`, `secret` and `timerRingHex` are written to
/// `record.encryptedValues`, so CloudKit encrypts them end to end with keys Apple
/// manages on the user's behalf. They are never stored as readable fields, and
/// the developer cannot read them from the CloudKit dashboard. Only `modifiedAt`,
/// `deleted`, `fingerprint`, `algorithm`, `digits` and `period` are plain fields —
/// none of which reveal a secret (`fingerprint` is a SHA-256; see
/// `SyncFingerprint`).
///
/// ### How records evolve
/// - Add / edit → the record is saved with a fresh `modifiedAt` and fingerprint.
/// - Delete → the record is kept as a **tombstone** (`deleted = 1`) with its
///   encrypted fields cleared, rather than being removed. A tombstone carries a
///   timestamp, so it can beat an older edit instead of losing to it, and it can
///   never be resurrected by a device that was offline when the delete happened.
///   Local tombstone bookkeeping is dropped past
///   `SyncMergeEngine.defaultTombstoneRetention`, but the CloudKit tombstone
///   record is kept: discarding it would shrink the window in which a deletion is
///   protected against a device that stayed offline longer than that.
/// - Conflict → last write wins on `modifiedAt`, with a deterministic tie-break.
///   Pushes use `savePolicy: .changedKeys`; if the server copy moved underneath
///   us CloudKit returns the server record, which we re-run through the merge
///   rules and retry once.
///
/// ### Availability
/// Every failure maps to a `CloudSyncStatus` the UI can show, and no failure ever
/// blocks local token management: the store keeps its own copy and simply retries
/// on the next edit, foreground, or silent push.
@MainActor
final class CloudKitTokenSyncService: TokenSyncService {
    /// Container declared by `Vaultic.entitlements`.
    static let containerIdentifier = "iCloud.com.eddingtontech.autheris"
    static let recordType = "AutherisToken"
    static let subscriptionID = "autheris-tokens-changed"

    /// Record types written by the abandoned sync implementation that was reverted
    /// before this feature shipped. Nothing reads them — the merge engine only ever
    /// sees `recordType` — but their rows can hold real, encrypted token secrets,
    /// so `deleteRemoteRecords()` includes them. Purging is the only thing this app
    /// does with them; there is deliberately no migration, because adopting the old
    /// format would mean depending on code that was removed on purpose.
    static let legacyRecordTypes = ["AutherisSyncRecord"]

    /// Every record type a "delete my iCloud data" request must remove.
    static var ownedRecordTypes: [String] { [recordType] + legacyRecordTypes }

    /// The exact CloudKit field names this app reads and writes.
    ///
    /// Centralised so the app cannot drift from its own schema. A typo in a raw
    /// string literal does not fail to compile — it silently creates a *new* field
    /// (or fails to read an existing one). That is exactly how the abandoned
    /// implementation ended up storing `timerRingHex` in the clear while its other
    /// secret-carrying fields were encrypted: `label`, `account` and `secret` went
    /// through `encryptedValues`, and `timerRingHex` was written as a plain field.
    ///
    /// Nothing in `encrypted` may be touched as a plain field — CloudKit refuses to
    /// treat a field as both, and only `record.encryptedValues` keeps it end-to-end
    /// encrypted.
    enum Field {
        // Plain fields. None of these reveal a secret.
        static let modifiedAt = "modifiedAt"
        static let deleted = "deleted"
        static let fingerprint = "fingerprint"
        static let algorithm = "algorithm"
        static let digits = "digits"
        static let period = "period"

        // End-to-end encrypted — read and written via `record.encryptedValues` only.
        static let label = "label"
        static let account = "account"
        static let secret = "secret"
        static let timerRingHex = "timerRingHex"

        static let plain = [modifiedAt, deleted, fingerprint, algorithm, digits, period]
        static let encrypted = [label, account, secret, timerRingHex]

        /// The complete field set the `AutherisToken` schema must define.
        static var all: [String] { plain + encrypted }
    }

    private static let pageSize = 400
    private static let maxPushAttempts = 2

    private let defaults: UserDefaults
    private let container: CKContainer
    private let database: CKDatabase

    private(set) var isEnabled: Bool
    private(set) var status: CloudSyncStatus
    private(set) var isAvailable = false
    var onStatusChange: ((CloudSyncStatus) -> Void)?

    private var isSyncing = false
    private var hasCheckedSubscription = false

    init(isEnabled: Bool, containerIdentifier: String = CloudKitTokenSyncService.containerIdentifier, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.container = CKContainer(identifier: containerIdentifier)
        self.database = container.privateCloudDatabase
        self.isEnabled = isEnabled
        self.status = isEnabled ? .synced(nil) : .disabled
    }

    // MARK: - Enablement

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        // Re-checking the subscription next time keeps a stale local flag from
        // skipping the install after the user signs into a different account.
        hasCheckedSubscription = false
        updateStatus(enabled ? .synced(nil) : .disabled)
    }

    /// Probes iCloud availability **regardless of whether sync is on**, because the
    /// Settings toggle needs to know whether enabling it can possibly succeed.
    /// Only `status` reflects the off state; `isAvailable` stays truthful.
    func refreshAvailability() async {
        do {
            let usable = try await hasUsableAccount()
            isAvailable = usable
            if !isEnabled {
                // Off is off, even if iCloud is reachable.
                updateStatus(.disabled)
            } else if !usable {
                isSyncing = false
                updateStatus(.accountUnavailable)
            }
        } catch {
            isAvailable = false
            updateStatus(isEnabled ? Self.status(for: error) : .disabled)
        }
    }

    // MARK: - Sync

    func sync(local: SyncLocalState) async -> SyncMergeOutcome? {
        guard isEnabled else { return nil }
        guard !isSyncing else { return nil }
        isSyncing = true
        defer { isSyncing = false }

        updateStatus(.syncing)
        do {
            guard try await hasUsableAccount() else {
                isAvailable = false
                updateStatus(.accountUnavailable)
                return nil
            }
            isAvailable = true

            try await installSubscriptionIfNeeded()

            let remote = try await fetchRemoteRecords()
            var outcome = SyncMergeEngine.merge(local: local, remote: remote)

            // A conflict during the push means another device wrote first. Fold
            // the server's winning copies back through the merge rules so this
            // device ends up with the same answer as everyone else.
            let adoptedDuringPush = try await push(outcome.uploads)
            if !adoptedDuringPush.isEmpty {
                outcome = SyncMergeEngine.merge(
                    local: SyncLocalState(tokens: outcome.tokens, tombstones: outcome.tombstones),
                    remote: adoptedDuringPush
                )
                outcome.uploads = []
            }

            defaults.set(Date(), forKey: Self.lastSyncedAtKey)
            updateStatus(.synced(defaults.object(forKey: Self.lastSyncedAtKey) as? Date))
            return outcome
        } catch {
            updateStatus(Self.status(for: error))
            return nil
        }
    }

    /// Removes **everything this app owns** in the private database: its own
    /// records, plus the records the abandoned sync implementation left behind
    /// (see `legacyRecordTypes`).
    ///
    /// The legacy pass matters for a deletion to mean what the user thinks it
    /// means — those rows hold real (encrypted) token secrets, and nothing in this
    /// app reads or migrates them, so without this they would survive a "delete
    /// from iCloud" and stay there unreachable.
    func deleteRemoteRecords() async throws {
        var recordIDs: [CKRecord.ID] = []
        for recordType in Self.ownedRecordTypes {
            // A type that was never written simply returns nothing.
            recordIDs.append(contentsOf: try await fetchObjects(ofType: recordType).map(\.recordID))
        }
        guard !recordIDs.isEmpty else { return }

        for chunk in stride(from: 0, to: recordIDs.count, by: Self.pageSize).map({ Array(recordIDs[$0..<min($0 + Self.pageSize, recordIDs.count)]) }) {
            let response = try await database.modifyRecords(
                saving: [],
                deleting: chunk,
                atomically: false
            )
            // `atomically: false` reports failures per record, so surface the first.
            for result in response.deleteResults.values {
                if case .failure(let error) = result { throw error }
            }
        }
        // Nothing left to reconcile against, so drop the local bookkeeping too.
        defaults.removeObject(forKey: Self.lastSyncedAtKey)
    }

    func handleRemoteNotification(userInfo: [AnyHashable: Any]) -> Bool {
        guard isEnabled else { return false }
        guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo) else { return false }
        switch notification.notificationType {
        case .database, .query, .recordZone:
            return true
        default:
            return false
        }
    }

    // MARK: - Account

    private func hasUsableAccount() async throws -> Bool {
        // Deliberately keyed only on `accountStatus`. `FileManager.ubiquityIdentityToken`
        // is `nil` unless the app *also* holds an iCloud Documents (ubiquity
        // container) entitlement, so gating on it would pin a CloudKit-only app
        // like this one at "not signed in" forever, even for a signed-in user.
        try await container.accountStatus() == .available
    }

    // MARK: - Subscription

    /// Installs a `CKDatabaseSubscription` so the private database can wake the
    /// app with a silent push instead of relying on the user reopening it.
    private func installSubscriptionIfNeeded() async throws {
        guard !hasCheckedSubscription else { return }
        let existing = try await database.allSubscriptions()
        hasCheckedSubscription = true
        guard !existing.contains(where: { $0.subscriptionID == Self.subscriptionID }) else { return }

        let subscription = CKDatabaseSubscription(subscriptionID: Self.subscriptionID)
        let info = CKSubscription.NotificationInfo()
        // Silent: no banner, just a background fetch on the receiving device.
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        do {
            _ = try await database.save(subscription)
        } catch let error as CKError where error.code == .serverRejectedRequest {
            // Already registered on the server from an earlier install.
        }
    }

    // MARK: - Fetch

    private func fetchRemoteRecords() async throws -> [SyncRecord] {
        try await fetchObjects(ofType: Self.recordType).compactMap { Self.decode($0) }
    }

    /// Paged fetch of every record of one type. The dataset is small (one record
    /// per token), so a full fetch is simpler and more robust than change tokens,
    /// and it means a missed push can never leave a device permanently stale.
    ///
    /// `recordType` is a parameter rather than a constant because the delete path
    /// also sweeps the legacy type; the sync path only ever passes `Self.recordType`.
    private func fetchObjects(ofType recordType: String) async throws -> [CKRecord] {
        do {
            return try await fetchPage(ofType: recordType)
        } catch let error as CKError where Self.isMissingRecordType(error) {
            // A container that has never stored a record of this type has no such
            // type yet, which is the same as "no records". Treating it as an error
            // would make the very first sync impossible; saving creates the type.
            return []
        }
    }

    private func fetchPage(ofType recordType: String) async throws -> [CKRecord] {
        var records: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        repeat {
            let response: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?)
            if let cursor {
                response = try await database.records(continuingMatchFrom: cursor, resultsLimit: Self.pageSize)
            } else {
                response = try await database.records(matching: query, resultsLimit: Self.pageSize)
            }
            for (_, result) in response.matchResults {
                if case .success(let record) = result { records.append(record) }
            }
            cursor = response.queryCursor
        } while cursor != nil
        return records
    }

    private static func isMissingRecordType(_ error: CKError) -> Bool {
        if error.code == .unknownItem { return true }
        let message = error.localizedDescription.lowercased()
        return message.contains("did not find record type") || message.contains("record type")
    }

    // MARK: - Push

    /// Uploads winning local records, returning any server copies that won a
    /// conflict so the caller can adopt them.
    private func push(_ uploads: [SyncRecord]) async throws -> [SyncRecord] {
        var pending = uploads.map { (item: $0, record: Self.encode($0)) }
        var adopted: [SyncRecord] = []

        for _ in 0..<Self.maxPushAttempts {
            guard !pending.isEmpty else { break }
            let response = try await database.modifyRecords(
                saving: pending.map(\.record),
                deleting: [],
                // Only send fields we changed, so two devices editing different
                // fields of one record do not clobber each other.
                savePolicy: .changedKeys,
                atomically: false
            )

            var retries: [(item: SyncRecord, record: CKRecord)] = []
            for (recordID, result) in response.saveResults {
                guard case .failure(let error) = result else { continue }
                guard let entry = pending.first(where: { $0.record.recordID == recordID }) else { continue }
                guard let serverRecord = Self.serverRecord(from: error),
                      let serverItem = Self.decode(serverRecord) else {
                    throw error
                }
                if SyncMergeEngine.localWins(entry.item, over: serverItem) {
                    // Ours is newer: re-apply our values onto the server's record
                    // so the retry carries a current change tag.
                    retries.append((entry.item, Self.encode(entry.item, into: serverRecord)))
                } else {
                    adopted.append(serverItem)
                }
            }
            pending = retries
        }
        // Anything still pending exhausted its retries; the next sync picks it up.
        return adopted
    }

    private static func serverRecord(from error: Error) -> CKRecord? {
        let userInfo = (error as NSError).userInfo
        if let record = userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord {
            return record
        }
        if let partial = userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error] {
            for itemError in partial.values {
                if let record = (itemError as NSError).userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord {
                    return record
                }
            }
        }
        return nil
    }

    // MARK: - Record <-> SyncRecord

    private static func decode(_ record: CKRecord) -> SyncRecord? {
        guard let modifiedAt = record[Field.modifiedAt] as? Date,
              let fingerprint = record[Field.fingerprint] as? String else { return nil }
        let id = record.recordID.recordName
        let deleted = (record[Field.deleted] as? NSNumber)?.boolValue ?? false

        guard !deleted else {
            return .tombstone(id: id, deletedAt: modifiedAt)
        }

        guard let uuid = UUID(uuidString: id),
              let label = record.encryptedValues[Field.label] as? String,
              let account = record.encryptedValues[Field.account] as? String,
              let secret = record.encryptedValues[Field.secret] as? String,
              let algorithmRaw = record[Field.algorithm] as? String,
              let algorithm = OTPAlgorithm(rawValue: algorithmRaw),
              let digits = (record[Field.digits] as? NSNumber)?.intValue,
              let period = (record[Field.period] as? NSNumber)?.intValue else {
            // A record we cannot interpret is skipped rather than guessed at; the
            // next sync will fetch the authoritative copy again.
            return nil
        }

        let token = OTPCode(
            id: uuid,
            label: label,
            account: account,
            secret: secret,
            algorithm: algorithm,
            digits: digits,
            period: period,
            timerRingHex: record.encryptedValues[Field.timerRingHex] as? String,
            modifiedAt: modifiedAt
        )
        return SyncRecord(id: id,
                          modifiedAt: modifiedAt,
                          deleted: false,
                          fingerprint: fingerprint,
                          token: token)
    }

    private static func encode(_ item: SyncRecord, into existing: CKRecord? = nil) -> CKRecord {
        let record = existing ?? CKRecord(recordType: recordType, recordID: CKRecord.ID(recordName: item.id))
        record[Field.modifiedAt] = item.modifiedAt as CKRecordValue
        record[Field.deleted] = NSNumber(value: item.deleted)
        record[Field.fingerprint] = item.fingerprint as CKRecordValue

        if item.deleted {
            // A tombstone must not leave recoverable material behind.
            for key in Field.encrypted { record.encryptedValues[key] = nil }
            for key in [Field.algorithm, Field.digits, Field.period] { record[key] = nil }
        } else if let token = item.token {
            record.encryptedValues[Field.label] = token.label as CKRecordValue
            record.encryptedValues[Field.account] = token.account as CKRecordValue
            record.encryptedValues[Field.secret] = token.secret as CKRecordValue
            // Assigned on both branches so an edit that drops a custom ring colour
            // clears the stored value instead of leaving the old one behind.
            if let ring = token.timerRingHex {
                record.encryptedValues[Field.timerRingHex] = ring as CKRecordValue
            } else {
                record.encryptedValues[Field.timerRingHex] = nil
            }
            record[Field.algorithm] = token.algorithm.rawValue as CKRecordValue
            record[Field.digits] = NSNumber(value: token.digits)
            record[Field.period] = NSNumber(value: token.period)
        }
        return record
    }

    // MARK: - Status

    private func updateStatus(_ newStatus: CloudSyncStatus) {
        status = newStatus
        onStatusChange?(newStatus)
    }

    private static func status(for error: Error) -> CloudSyncStatus {
        let message = error.localizedDescription.lowercased()
        guard let cloudError = error as? CKError else {
            return .failed(error.localizedDescription)
        }
        switch cloudError.code {
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return .waitingForNetwork
        case .notAuthenticated, .permissionFailure, .accountTemporarilyUnavailable, .managedAccountRestricted:
            return .accountUnavailable
        case .unknownItem:
            return .unavailable("The Autheris CloudKit schema has not been deployed yet.")
        default:
            // CloudKit refuses an unfiltered query unless the system `recordName`
            // field carries a Queryable index, and a record type created implicitly
            // by saving gets no indexes. So this is expected on a container whose
            // schema has never been tuned, and it is actionable rather than a bug —
            // report it as such instead of a generic sync failure.
            if message.contains("not marked queryable") {
                return .unavailable("Autheris can't read your iCloud data yet: the CloudKit schema needs a Queryable index on recordName (CloudKit Console → Schema → Indexes).")
            }
            if message.contains("entitlement") || message.contains("container") {
                return .unavailable("This build is not configured for iCloud. Add the iCloud capability to the Autheris target.")
            }
            return .failed(describe(error))
        }
    }

    /// Renders a `CKError` into something worth showing a user, including the
    /// per-record reasons hidden inside a partial failure.
    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        var message = error.localizedDescription
        if let cloudError = error as? CKError {
            message = "iCloud error \(cloudError.code.rawValue): \(message)"
            if cloudError.code == .partialFailure,
               let partialErrors = cloudError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error] {
                let details = partialErrors
                    .map { key, itemError in "\(key): \(itemError.localizedDescription)" }
                    .sorted()
                    .joined(separator: "; ")
                if !details.isEmpty {
                    message += " [\(details)]"
                }
            }
        } else if nsError.domain != NSURLErrorDomain {
            message = "\(nsError.domain) \(nsError.code): \(message)"
        }
        return message
    }
}

extension CloudKitTokenSyncService {
    /// Read by the store to render "Last updated …" without re-querying CloudKit.
    static let lastSyncedAtKey = "icloudSyncLastSyncedAt"
}

import CloudKit
import Foundation

#if os(macOS)
// For the pre-flight entitlement check that stops an unentitled build from
// asking CloudKit for a container it cannot have. See `configurationProblem`.
import Security
#endif

/// Raised before CloudKit is touched when this build cannot use it at all.
///
/// A plain error rather than a `CKError`, because in this case no CloudKit call
/// is ever made — there is no CloudKit error to receive. It maps onto
/// `CloudSyncStatus.unavailable`, the state Settings already renders in red.
struct CloudKitUnavailableError: LocalizedError {
    let reason: String

    var errorDescription: String? { reason }
}

/// The one CloudKit call a push makes.
///
/// A protocol so tests can answer it the way the server does when another device
/// wrote first — which is the path that never ran while uploads used
/// `.changedKeys`, and nothing could show it.
nonisolated protocol CloudRecordSaving {
    func modifyRecords(
        saving recordsToSave: [CKRecord],
        deleting recordIDsToDelete: [CKRecord.ID],
        savePolicy: CKModifyRecordsOperation.RecordSavePolicy,
        atomically: Bool
    ) async throws -> (saveResults: [CKRecord.ID: Result<CKRecord, any Error>],
                       deleteResults: [CKRecord.ID: Result<Void, any Error>])
}

extension CKDatabase: CloudRecordSaving {}

/// Syncs tokens through the user's **private** CloudKit database.
///
/// ### Where the secrets live
/// `label`, `account`, `secret`, `timerRingHex` and `isPinned` are written to
/// `record.encryptedValues`, so CloudKit encrypts them end to end with keys Apple
/// manages on the user's behalf. They are never stored as readable fields, and
/// the developer cannot read them from the CloudKit dashboard. Only `modifiedAt`,
/// `deleted`, `fingerprint`, `algorithm`, `digits` and `period` are plain fields —
/// none of which reveal a secret (`fingerprint` is a SHA-256; see
/// `SyncFingerprint`).
///
/// `isPinned` is not a secret, but it is still a statement about *which accounts
/// matter to this user*, so it is encrypted alongside the label rather than left
/// readable on Apple's servers. It must never be written as a plain field.
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
///   Uploads are written onto the records this sync fetched, so they carry the
///   server's change tags, and saved with `.ifServerRecordUnchanged`. If another
///   device wrote in between, CloudKit refuses the save and returns its copy,
///   which we re-run through the merge rules and retry once. (`.changedKeys`
///   compares no change tags at all, so with it a stale device simply overwrote
///   the newer copy.)
///
/// ### Availability
/// Every failure maps to a `CloudSyncStatus` the UI can show, and no failure ever
/// blocks local token management: the store keeps its own copy and simply retries
/// on the next edit, foreground, or silent push.
@MainActor
final class CloudKitTokenSyncService: TokenSyncService {
    /// Container declared by `Vaultic.entitlements`.
    ///
    /// `nonisolated` because it is read as the default value of `init`'s
    /// `containerIdentifier` parameter, and a default argument is evaluated
    /// outside the actor — the same reason `OTPDataStore.syncEnabledKey` is.
    nonisolated static let containerIdentifier = "iCloud.com.eddingtontech.autheris"
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
        /// Time-based or counter-based (`OTPKind`'s raw value).
        ///
        /// Plain for the same reason `algorithm` is: it is a property of the code's
        /// *construction*, not of the account, and it is what the fingerprint needs
        /// to see. Unlike the legacy `AutherisSyncRecord` type's own `kind` field,
        /// which is unrelated — CloudKit fields are per record type, so the two
        /// cannot collide.
        static let kind = "kind"
        /// How many codes a counter-based token has produced.
        ///
        /// Plain, like `digits` and `period`: a count of uses is not a secret, and
        /// it has to be comparable without decrypting for the fingerprint to work.
        /// An `Int64` — `OTPCode.maximumCounter` is bounded by that on purpose.
        static let counter = "counter"

        // End-to-end encrypted — read and written via `record.encryptedValues` only.
        //
        // Every field here holds a **String**, including the boolean `isPinned`
        // (see `EncryptedBool`). Keep it that way: this is the only encrypted field
        // shape proven against the production container, and a CloudKit field's
        // type is fixed once it exists, so a different type cannot be corrected
        // later — only replaced with a new field name.
        static let label = "label"
        static let account = "account"
        static let secret = "secret"
        static let timerRingHex = "timerRingHex"
        static let isPinned = "isPinned"

        static let plain = [modifiedAt, deleted, fingerprint, algorithm, digits, period, kind, counter]
        static let encrypted = [label, account, secret, timerRingHex, isPinned]

        /// The complete field set the `AutherisToken` schema must define.
        static var all: [String] { plain + encrypted }
    }

    private static let pageSize = 400
    private static let maxPushAttempts = 2

    private let defaults: UserDefaults
    private let containerIdentifier: String
    /// Built on first use rather than in `init` — see `container()` for why.
    private var containerStorage: CKContainer?

    private(set) var isEnabled: Bool
    private(set) var status: CloudSyncStatus
    private(set) var isAvailable = false
    var onStatusChange: ((CloudSyncStatus) -> Void)?

    private var isSyncing = false
    private var hasCheckedSubscription = false

    init(isEnabled: Bool, containerIdentifier: String = CloudKitTokenSyncService.containerIdentifier, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.containerIdentifier = containerIdentifier
        self.isEnabled = isEnabled
        // Say up front that this build cannot use CloudKit, rather than showing a
        // "Synced" that the first availability probe then has to contradict.
        if let problem = Self.configurationProblem(forContainer: containerIdentifier) {
            self.status = .unavailable(problem)
        } else {
            self.status = isEnabled ? .synced(nil) : .disabled
        }
    }

    // MARK: - Container

    /// The CloudKit container, built on first use.
    ///
    /// **Deliberately not built in `init`.** `CKContainer(identifier:)` does not
    /// throw when the app lacks the CloudKit entitlement — it raises an
    /// Objective-C exception, which terminates the process. `OTPDataStore`
    /// constructs this service whether or not the user has turned sync on, so
    /// building the container eagerly turned "this build has no iCloud
    /// entitlement" into "the app crashes at launch, before any UI appears, even
    /// with sync switched off". That is exactly what the first unsigned macOS
    /// build did — and on a shipping app the same shape means a misconfigured App
    /// ID crashes for every user instead of degrading.
    ///
    /// Building it here means such a build starts, runs, and reports
    /// `.unavailable` from Settings. That is the state `CloudSyncStatus` and the
    /// `status(for:)` branch below were already written for, but could never
    /// reach: the container raised before any error could be formed.
    private func container() throws -> CKContainer {
        if let containerStorage { return containerStorage }

        if let problem = Self.configurationProblem(forContainer: containerIdentifier) {
            throw CloudKitUnavailableError(reason: problem)
        }

        let container = CKContainer(identifier: containerIdentifier)
        containerStorage = container
        return container
    }

    private func cloudDatabase() throws -> CKDatabase {
        try container().privateCloudDatabase
    }

    /// A reason this build cannot use CloudKit at all, or `nil` when its
    /// entitlements look right.
    ///
    /// The check has to happen *before* a container exists, and it cannot ask
    /// CloudKit, so it reads the app's own code signature instead. macOS only:
    /// `SecTaskCreateFromSelf` is not in the public iOS SDK, and an unentitled
    /// iOS build is not something that ships — App Store, TestFlight and device
    /// builds all carry the entitlement. On iOS the first CloudKit *use* still
    /// raises in that case; what deferring it buys there is that it no longer
    /// happens during launch.
    private static func configurationProblem(forContainer identifier: String) -> String? {
        #if os(macOS)
        guard let services = entitlementsValue("com.apple.developer.icloud-services"),
              // A development profile grants `*` rather than naming CloudKit.
              services.contains(where: { $0 == "CloudKit" || $0 == "*" }) else {
            return "This build is not configured for iCloud. Add the iCloud capability to the Autheris target."
        }
        guard let containers = entitlementsValue("com.apple.developer.icloud-container-identifiers"),
              containers.contains(identifier) else {
            return "This build is not entitled to the \(identifier) iCloud container."
        }
        return nil
        #else
        return nil
        #endif
    }

    #if os(macOS)
    /// Reads one entitlement out of this process's own code signature. Reading
    /// *self* needs no special permission.
    private static func entitlementsValue(_ key: String) -> [String]? {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, key as CFString, nil) else { return nil }
        return value as? [String]
    }
    #endif

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
            // A build that cannot reach CloudKit at all keeps saying so, even with
            // sync off — the status row is the only place the user can find out
            // that turning it on will not help.
            if let unavailable = error as? CloudKitUnavailableError {
                updateStatus(.unavailable(unavailable.reason))
            } else {
                updateStatus(isEnabled ? Self.status(for: error) : .disabled)
            }
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

            let fetched = try await fetchObjects(ofType: Self.recordType)
            let remote = fetched.compactMap { Self.decode($0) }
            var outcome = SyncMergeEngine.merge(local: local, remote: remote)

            // A conflict during the push means another device wrote first. Fold
            // the server's winning copies back through the merge rules so this
            // device ends up with the same answer as everyone else.
            let serverRecords = Dictionary(fetched.map { ($0.recordID.recordName, $0) },
                                           uniquingKeysWith: { first, _ in first })
            let database = try cloudDatabase()
            let adoptedDuringPush = try await Self.push(outcome.uploads, onto: serverRecords, using: database)
            if !adoptedDuringPush.isEmpty {
                outcome = SyncMergeEngine.merge(
                    local: SyncLocalState(tokens: outcome.tokens, tombstones: outcome.tombstones),
                    remote: adoptedDuringPush
                )
                outcome.uploads = []
            }

            // Best effort: a failure here leaves the next sync to try again, and
            // must not report the sync itself as failed.
            try? await Self.scrubTombstones(in: fetched, skipping: Set(outcome.uploads.map(\.id)),
                                            using: database)

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
            let response = try await cloudDatabase().modifyRecords(
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
        try await container().accountStatus() == .available
    }

    // MARK: - Subscription

    /// Installs a `CKDatabaseSubscription` so the private database can wake the
    /// app with a silent push instead of relying on the user reopening it.
    private func installSubscriptionIfNeeded() async throws {
        guard !hasCheckedSubscription else { return }
        let existing = try await cloudDatabase().allSubscriptions()
        hasCheckedSubscription = true
        guard !existing.contains(where: { $0.subscriptionID == Self.subscriptionID }) else { return }

        let subscription = CKDatabaseSubscription(subscriptionID: Self.subscriptionID)
        let info = CKSubscription.NotificationInfo()
        // Silent: no banner, just a background fetch on the receiving device.
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        do {
            _ = try await cloudDatabase().save(subscription)
        } catch let error as CKError where error.code == .serverRejectedRequest {
            // Already registered on the server from an earlier install.
        }
    }

    // MARK: - Fetch

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
                response = try await cloudDatabase().records(continuingMatchFrom: cursor, resultsLimit: Self.pageSize)
            } else {
                response = try await cloudDatabase().records(matching: query, resultsLimit: Self.pageSize)
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
    ///
    /// Each upload is written onto `serverRecords`' copy when there is one — what
    /// this sync fetched — so it carries that copy's change tag. A record that is
    /// new to the server starts fresh, and if another device created it meanwhile
    /// that is a conflict like any other.
    static func push(_ uploads: [SyncRecord],
                     onto serverRecords: [String: CKRecord],
                     using database: CloudRecordSaving) async throws -> [SyncRecord] {
        var pending = uploads.map { (item: $0, record: Self.encode($0, into: serverRecords[$0.id])) }
        var adopted: [SyncRecord] = []

        for _ in 0..<Self.maxPushAttempts {
            guard !pending.isEmpty else { break }
            let response = try await database.modifyRecords(
                saving: pending.map(\.record),
                deleting: [],
                // Refused when the server's copy has changed since it was fetched,
                // which is what makes a stale device find out instead of
                // overwriting. Only changed keys are sent either way.
                savePolicy: .ifServerRecordUnchanged,
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

    /// Clears the encrypted fields still left on tombstones.
    ///
    /// Earlier versions wrote a tombstone onto a fresh record with `.changedKeys`,
    /// and setting a key that was never set on that record to `nil` is not a
    /// change — so the old label, account and secret could stay on the server
    /// under a record that says it was deleted. Tombstones written now start from
    /// the fetched record and clear properly; this catches the ones already there.
    /// `skipping` is the records this sync has just uploaded.
    static func scrubTombstones(in fetched: [CKRecord],
                                skipping uploaded: Set<String>,
                                using database: CloudRecordSaving) async throws {
        let leftovers = fetched.filter { record in
            (record[Field.deleted] as? NSNumber)?.boolValue == true
                && !uploaded.contains(record.recordID.recordName)
                && Field.encrypted.contains { record.encryptedValues[$0] != nil }
        }
        guard !leftovers.isEmpty else { return }
        for record in leftovers {
            for key in Field.encrypted { record.encryptedValues[key] = nil }
        }
        // A conflict means another device wrote the record since, and it will be
        // looked at again on the next sync.
        _ = try await database.modifyRecords(saving: leftovers, deleting: [],
                                             savePolicy: .ifServerRecordUnchanged,
                                             atomically: false)
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

    /// Internal rather than private so tests can build records the way the
    /// server would hold them.
    static func decode(_ record: CKRecord) -> SyncRecord? {
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
            // Both absent on every record written before counter-based codes
            // existed, which is exactly what `.totp` and `0` mean — and a `kind`
            // this build does not recognise reads as time-based rather than skipping
            // the record, because one unreadable field should not cost the user the
            // token. Deliberately *not* part of the `guard` above for that reason.
            kind: OTPKind(rawValue: (record[Field.kind] as? String) ?? "") ?? .totp,
            counter: (record[Field.counter] as? NSNumber)?.uint64Value ?? 0,
            timerRingHex: record.encryptedValues[Field.timerRingHex] as? String,
            // Absent on every record written before pinning existed, which is
            // exactly what `false` means. See `EncryptedBool` for why this is a
            // string rather than a number.
            isPinned: EncryptedBool.value(record.encryptedValues[Field.isPinned]),
            modifiedAt: modifiedAt
        )
        return SyncRecord(id: id,
                          modifiedAt: modifiedAt,
                          deleted: false,
                          fingerprint: fingerprint,
                          token: token)
    }

    static func encode(_ item: SyncRecord, into existing: CKRecord? = nil) -> CKRecord {
        let record = existing ?? CKRecord(recordType: recordType, recordID: CKRecord.ID(recordName: item.id))
        record[Field.modifiedAt] = item.modifiedAt as CKRecordValue
        record[Field.deleted] = NSNumber(value: item.deleted)
        record[Field.fingerprint] = item.fingerprint as CKRecordValue

        if item.deleted {
            // A tombstone must not leave recoverable material behind.
            for key in Field.encrypted { record.encryptedValues[key] = nil }
            for key in [Field.algorithm, Field.digits, Field.period, Field.kind, Field.counter] { record[key] = nil }
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
            record.encryptedValues[Field.isPinned] = EncryptedBool.text(token.isPinned) as CKRecordValue
            record[Field.algorithm] = token.algorithm.rawValue as CKRecordValue
            record[Field.digits] = NSNumber(value: token.digits)
            record[Field.period] = NSNumber(value: token.period)
            record[Field.kind] = token.kind.rawValue as CKRecordValue
            // `Int64`, which is what the field is created as and what
            // `OTPCode.maximumCounter` bounds the value to.
            record[Field.counter] = NSNumber(value: token.counter)
        }
        return record
    }

    // MARK: - Status

    private func updateStatus(_ newStatus: CloudSyncStatus) {
        status = newStatus
        onStatusChange?(newStatus)
    }

    private static func status(for error: Error) -> CloudSyncStatus {
        // Raised by `container()` before CloudKit is touched, so it is the one
        // failure that arrives as neither a `CKError` nor an ongoing sync problem.
        if let unavailable = error as? CloudKitUnavailableError {
            return .unavailable(unavailable.reason)
        }
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

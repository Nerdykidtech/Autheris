import CloudKit
import Foundation

/// The intentionally small status surface exposed by the optional sync feature.
enum CloudSyncStatus: Equatable {
    case disabled
    case idle
    case syncing
    case offline
    case accountUnavailable
    case unavailable
    case schemaUnavailable
    case error(String)

    var title: String {
        switch self {
        case .disabled: return "Sync is off"
        case .idle: return "Up to date"
        case .syncing: return "Syncing…"
        case .offline: return "Waiting for network"
        case .accountUnavailable: return "iCloud account unavailable"
        case .unavailable: return "Unavailable in Simulator"
        case .schemaUnavailable: return "CloudKit schema not deployed"
        case .error: return "Sync error"
        }
    }

    var detail: String? {
        if case .error(let message) = self {
            return message
        }
        return nil
    }
}

struct CloudSyncResult {
    let codes: [OTPCode]
    let settings: [String: Bool]
}

/// CloudKit's private database is opt-in. Nothing is sent to CloudKit until
/// `setEnabled(true)` is called by the Settings screen.
final class CloudKitSyncService {
    static let enabledKey = "icloudSyncEnabled"
    static let metadataKey = "icloudSyncMetadata.v1"
    static let syncAnchorKey = "icloudSyncAnchor.v1"
    static let legacyMigrationKey = "icloudSyncLegacyMigration.v1"

    static let privacySettingKeys = ["enablePrivacyBlur", "hideCodesInAppSwitcher"]
    private static let recordType = "AutherisSyncRecord"

    struct Metadata: Codable {
        var kind: String
        var updatedAt: Date
        var deleted: Bool
        var contentHash: String
        var serverModifiedAt: Date? = nil
    }

    private let defaults: UserDefaults
    private lazy var container: CKContainer = CKContainer.default()
    private lazy var database: CKDatabase = container.privateCloudDatabase
    private var metadata: [String: Metadata] = [:]
    private var pendingWorkItem: DispatchWorkItem?
    private var currentCodes: [OTPCode] = []
    private var currentSettings: [String: Bool] = [:]
    private var isSyncInProgress = false
    private var fetchAnchor: Date?

    private static var isCloudKitSupported: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return true
        #endif
    }

    private(set) var isEnabled: Bool
    private(set) var status: CloudSyncStatus
    var onStatusChange: ((CloudSyncStatus) -> Void)?
    var onSyncCompleted: ((CloudSyncResult) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isEnabled = defaults.bool(forKey: Self.enabledKey)
        self.status = isEnabled ? .idle : .disabled
        if let data = defaults.data(forKey: Self.metadataKey),
           let decoded = try? JSONDecoder().decode([String: Metadata].self, from: data) {
            metadata = decoded
        }
    }

    func setEnabled(_ enabled: Bool, codes: [OTPCode], settings: [String: Bool]) {
        pendingWorkItem?.cancel()
        guard !enabled || Self.isCloudKitSupported else {
            isEnabled = false
            defaults.set(false, forKey: Self.enabledKey)
            updateStatus(.unavailable)
            return
        }
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledKey)
        if !enabled {
            updateStatus(.disabled)
            return
        }

        currentCodes = codes
        currentSettings = settings
        // Existing UserDefaults data is the migration source. It is stamped
        // only once, so subsequent saves retain their original timestamps.
        if defaults.bool(forKey: Self.legacyMigrationKey) == false {
            noteLocalState(codes: codes, settings: settings, schedule: false)
            defaults.set(true, forKey: Self.legacyMigrationKey)
        } else {
            noteLocalState(codes: codes, settings: settings, schedule: false)
        }
        syncNow(codes: codes, settings: settings)
    }

    func noteLocalState(codes: [OTPCode], settings: [String: Bool], schedule: Bool = true) {
        guard isEnabled else { return }
        currentCodes = codes
        currentSettings = settings

        let now = Date()
        var seen = Set<String>()
        for code in codes {
            let key = code.id.uuidString
            seen.insert(key)
            let hash = tokenHash(code)
            if metadata[key]?.contentHash != hash || metadata[key]?.deleted == true {
                metadata[key] = Metadata(kind: "token", updatedAt: now, deleted: false, contentHash: hash)
            } else if metadata[key] == nil {
                metadata[key] = Metadata(kind: "token", updatedAt: now, deleted: false, contentHash: hash)
            }
        }

        // A tombstone is retained locally and in CloudKit rather than deleting
        // the record, allowing a deletion to win over an older edit offline.
        let deletedTokenKeys = metadata.compactMap { key, value in
            value.kind == "token" && !seen.contains(key) && !value.deleted ? key : nil
        }
        for key in deletedTokenKeys {
            guard let value = metadata[key] else { continue }
            metadata[key] = Metadata(kind: "token", updatedAt: now, deleted: true, contentHash: value.contentHash)
        }

        for key in Self.privacySettingKeys {
            guard let setting = settings[key] else { continue }
            let recordKey = settingRecordName(key)
            let hash = settingHash(setting)
            if metadata[recordKey]?.contentHash != hash || metadata[recordKey]?.deleted == true {
                metadata[recordKey] = Metadata(kind: "setting", updatedAt: now, deleted: false, contentHash: hash)
            } else if metadata[recordKey] == nil {
                metadata[recordKey] = Metadata(kind: "setting", updatedAt: now, deleted: false, contentHash: hash)
            }
        }
        persistMetadata()
        if schedule { scheduleSync() }
    }

    func syncNow(codes: [OTPCode], settings: [String: Bool]) {
        guard isEnabled else { return }
        guard Self.isCloudKitSupported else {
            updateStatus(.unavailable)
            return
        }
        pendingWorkItem?.cancel()
        currentCodes = codes
        currentSettings = settings
        noteLocalState(codes: codes, settings: settings, schedule: false)
        guard !isSyncInProgress else { return }
        isSyncInProgress = true
        updateStatus(.syncing)

        container.accountStatus { [weak self] accountStatus, error in
            guard let self else { return }
            DispatchQueue.main.async {
                if let error {
                    self.finishWith(error: error)
                } else if accountStatus != .available {
                    self.isSyncInProgress = false
                    self.updateStatus(.accountUnavailable)
                } else {
                    self.fetchRemoteRecords()
                }
            }
        }
    }

    func deleteAllCloudData(completion: @escaping (Result<Void, Error>) -> Void) {
        guard Self.isCloudKitSupported else {
            let error = NSError(
                domain: "CloudKitSyncService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "iCloud data management is unavailable in Simulator."]
            )
            updateStatus(.error(error.localizedDescription))
            completion(.failure(error))
            return
        }
        fetchAllRemoteIDs { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.finishWith(error: error)
                completion(.failure(error))
            case .success(let ids):
                guard !ids.isEmpty else {
                    completion(.success(()))
                    return
                }
                let operation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: ids)
                operation.modifyRecordsCompletionBlock = { _, _, error in
                    DispatchQueue.main.async {
                        if let error {
                            self.finishWith(error: error)
                            completion(.failure(error))
                        } else {
                            self.metadata.removeAll()
                            self.persistMetadata()
                            self.defaults.removeObject(forKey: Self.syncAnchorKey)
                            completion(.success(()))
                        }
                    }
                }
                self.database.add(operation)
            }
        }
    }

    // MARK: - Fetch and merge

    private func fetchRemoteRecords(cursor: CKQueryOperation.Cursor? = nil, accumulated: [CKRecord] = []) {
        let operation: CKQueryOperation
        if let cursor {
            operation = CKQueryOperation(cursor: cursor)
        } else {
            // Fetch the complete private dataset. Using a local wall-clock
            // timestamp as a CloudKit modification anchor can miss changes
            // when device and server clocks differ.
            fetchAnchor = nil
            operation = CKQueryOperation(query: CKQuery(recordType: Self.recordType, predicate: NSPredicate(value: true)))
        }
        var records = accumulated
        operation.recordFetchedBlock = { records.append($0) }
        operation.queryCompletionBlock = { [weak self] cursor, error in
            guard let self else { return }
            DispatchQueue.main.async {
                if let error {
                    self.finishWith(error: error)
                } else if let cursor {
                    self.fetchRemoteRecords(cursor: cursor, accumulated: records)
                } else {
                    self.mergeAndPush(remoteRecords: records)
                }
            }
        }
        operation.resultsLimit = 400
        database.add(operation)
    }

    private func mergeAndPush(remoteRecords: [CKRecord]) {
        var remoteByID = Dictionary(uniqueKeysWithValues: remoteRecords.map { ($0.recordID.recordName, $0) })
        var mergedCodes = currentCodes
        var mergedSettings = currentSettings
        var recordsToSave: [CKRecord] = []

        for record in remoteRecords {
            guard let remote = decode(record) else { continue }
            let key = record.recordID.recordName
            let remoteDate = remote.updatedAt
            let localMetadata = metadata[key]
            let localDate = localMetadata?.updatedAt ?? .distantPast
            let remoteServerDate = record.modificationDate ?? .distantPast
            let localServerDate = localMetadata?.serverModifiedAt ?? .distantPast
            let localIsDirty = localMetadata.map {
                $0.contentHash != remote.contentHash || $0.deleted != remote.deleted
            } ?? false
            let remoteIsNewer = remoteServerDate > localServerDate ||
                (remoteServerDate == localServerDate && remoteDate > (localMetadata?.updatedAt ?? .distantPast))
            if remoteIsNewer && !localIsDirty {
                metadata[key] = Metadata(kind: remote.kind, updatedAt: remoteDate, deleted: remote.deleted,
                                         contentHash: remote.contentHash, serverModifiedAt: record.modificationDate)
                if remote.kind == "token" {
                    mergedCodes.removeAll { $0.id.uuidString == key }
                    if !remote.deleted, let token = remote.token { mergedCodes.append(token) }
                } else if remote.kind == "setting", let key = remote.settingKey,
                          Self.privacySettingKeys.contains(key), let value = remote.setting, !remote.deleted {
                    mergedSettings[key] = value
                }
            } else if (localIsDirty || localDate >= remoteDate),
                      let local = localItem(for: key, codes: mergedCodes, settings: mergedSettings) {
                // Reuse the fetched record so CloudKit can safely apply its
                // change tag; this is important when two devices edited offline.
                recordsToSave.append(encode(local, into: record))
            }
            remoteByID[key] = record
        }

        for (key, localMetadata) in metadata {
            guard localMetadata.kind == "token" || localMetadata.kind == "setting" else { continue }
            let localDate = localMetadata.updatedAt
            let remoteMetadata = remoteByID[key].flatMap(decode)
            let localIsDirty = remoteMetadata.map {
                localMetadata.contentHash != $0.contentHash || localMetadata.deleted != $0.deleted
            } ?? true
            guard let local = localItem(for: key, codes: mergedCodes, settings: mergedSettings) else {
                // The item is a local tombstone. If CloudKit did not return an
                // existing record, create one so the deletion can propagate.
                if remoteByID[key] == nil {
                    recordsToSave.append(encode(SyncItem.tombstone(key: key, metadata: localMetadata)))
                } else if localIsDirty || localDate >= (remoteMetadata?.updatedAt ?? .distantPast),
                          !recordsToSave.contains(where: { $0.recordID.recordName == key }) {
                    recordsToSave.append(encode(SyncItem.tombstone(key: key, metadata: localMetadata), into: remoteByID[key]))
                }
                continue
            }
            if remoteByID[key] == nil {
                recordsToSave.append(encode(local))
            } else if localIsDirty || localDate >= (remoteMetadata?.updatedAt ?? .distantPast) {
                if !recordsToSave.contains(where: { $0.recordID.recordName == key }) {
                    recordsToSave.append(encode(local, into: remoteByID[key]))
                }
            }
        }

        currentCodes = mergedCodes.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
        currentSettings = mergedSettings
        persistMetadata()
        if recordsToSave.isEmpty {
            finish(codes: currentCodes, settings: currentSettings)
        } else {
            fetchExistingRecordsBeforePush(recordsToSave) { [weak self] records in
                self?.push(records: records)
            }
        }
    }

    private func fetchExistingRecordsBeforePush(_ records: [CKRecord], completion: @escaping ([CKRecord]) -> Void) {
        let ids = records.map(\.recordID)
        let operation = CKFetchRecordsOperation(recordIDs: ids)
        operation.fetchRecordsCompletionBlock = { [weak self] existing, error in
            DispatchQueue.main.async {
                guard let self else { return }
                // Missing records are expected during a first upload. CloudKit
                // reports a batch containing missing IDs as partialFailure.
                if let error, !self.isExpectedMissingRecordError(error) {
                    self.finishWith(error: error)
                    return
                }
                let existingByID = existing ?? [:]
                let refreshed = records.map { pending in
                    guard let old = existingByID[pending.recordID], let item = self.decode(pending) else {
                        return pending
                    }
                    return self.encode(item, into: old)
                }
                completion(refreshed)
            }
        }
        database.add(operation)
    }

    private func isExpectedMissingRecordError(_ error: Error) -> Bool {
        guard let cloudError = error as? CKError else {
            return (error as NSError).code == CKError.unknownItem.rawValue
        }
        if cloudError.code == .unknownItem {
            return true
        }
        guard cloudError.code == .partialFailure,
              let partialErrors = cloudError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error] else {
            return false
        }
        return partialErrors.values.allSatisfy { itemError in
            (itemError as NSError).code == CKError.unknownItem.rawValue
        }
    }

    private func push(records: [CKRecord], retryCount: Int = 0) {
        let operation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
        operation.savePolicy = .changedKeys
        operation.modifyRecordsCompletionBlock = { [weak self] saved, _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    if retryCount == 0, self.isRetryableModifyError(error) {
                        self.fetchExistingRecordsBeforePush(records) { [weak self] refreshedRecords in
                            self?.push(records: refreshedRecords, retryCount: 1)
                        }
                        return
                    }
                    self.finishWith(error: error)
                } else {
                    for record in saved ?? [] {
                        if let item = self.decode(record) {
                            self.metadata[record.recordID.recordName] = Metadata(
                                kind: item.kind,
                                updatedAt: item.updatedAt,
                                deleted: item.deleted,
                                contentHash: item.contentHash,
                                serverModifiedAt: record.modificationDate
                            )
                        }
                    }
                    self.persistMetadata()
                    self.finish(codes: self.currentCodes, settings: self.currentSettings)
                }
            }
        }
        database.add(operation)
    }

    private func isRetryableModifyError(_ error: Error) -> Bool {
        guard let cloudError = error as? CKError else { return false }
        if cloudError.code == .serverRejectedRequest || cloudError.code == .batchRequestFailed {
            return true
        }
        guard cloudError.code == .partialFailure,
              let partialErrors = cloudError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error] else {
            return false
        }
        return partialErrors.values.contains { itemError in
            guard let itemCloudError = itemError as? CKError else { return false }
            return itemCloudError.code == .serverRejectedRequest ||
                itemCloudError.code == .batchRequestFailed ||
                itemCloudError.code == .changeTokenExpired
        }
    }

    private func fetchAllRemoteIDs(completion: @escaping (Result<[CKRecord.ID], Error>) -> Void) {
        let query = CKQuery(recordType: Self.recordType, predicate: NSPredicate(value: true))
        let operation = CKQueryOperation(query: query)
        var ids: [CKRecord.ID] = []
        operation.recordFetchedBlock = { ids.append($0.recordID) }
        operation.queryCompletionBlock = { cursor, error in
            DispatchQueue.main.async {
                if let error {
                    completion(.failure(error))
                } else if let cursor {
                    self.fetchAllRemoteIDsPage(cursor: cursor, accumulated: ids, completion: completion)
                } else {
                    completion(.success(ids))
                }
            }
        }
        operation.resultsLimit = 400
        database.add(operation)
    }

    private func fetchAllRemoteIDsPage(cursor: CKQueryOperation.Cursor, accumulated: [CKRecord.ID],
                                       completion: @escaping (Result<[CKRecord.ID], Error>) -> Void) {
        let operation = CKQueryOperation(cursor: cursor)
        var ids = accumulated
        operation.recordFetchedBlock = { ids.append($0.recordID) }
        operation.queryCompletionBlock = { cursor, error in
            DispatchQueue.main.async {
                if let error {
                    completion(.failure(error))
                } else if let cursor {
                    self.fetchAllRemoteIDsPage(cursor: cursor, accumulated: ids, completion: completion)
                } else {
                    completion(.success(ids))
                }
            }
        }
        operation.resultsLimit = 400
        database.add(operation)
    }

    // MARK: - Records

    private struct SyncItem {
        let key: String
        let kind: String
        let updatedAt: Date
        let deleted: Bool
        let contentHash: String
        let token: OTPCode?
        let settingKey: String?
        let setting: Bool?

        static func tombstone(key: String, metadata: Metadata) -> SyncItem {
            SyncItem(key: key, kind: metadata.kind, updatedAt: metadata.updatedAt, deleted: true,
                     contentHash: metadata.contentHash, token: nil, settingKey: nil, setting: nil)
        }
    }

    private func localItem(for key: String, codes: [OTPCode], settings: [String: Bool]) -> SyncItem? {
        guard let item = metadata[key] else { return nil }
        if item.kind == "token", let token = codes.first(where: { $0.id.uuidString == key }) {
            return SyncItem(key: key, kind: "token", updatedAt: item.updatedAt, deleted: false,
                            contentHash: item.contentHash, token: token, settingKey: nil, setting: nil)
        }
        if item.kind == "setting", let settingKey = settingKey(for: key), let value = settings[settingKey] {
            return SyncItem(key: key, kind: "setting", updatedAt: item.updatedAt, deleted: false,
                            contentHash: item.contentHash, token: nil, settingKey: settingKey, setting: value)
        }
        return nil
    }

    private func decode(_ record: CKRecord) -> SyncItem? {
        guard let kind = record["kind"] as? String,
              let updatedAt = record["updatedAt"] as? Date else { return nil }
        let deleted = (record["deleted"] as? NSNumber)?.boolValue ?? false
        if kind == "token", deleted {
            return SyncItem(key: record.recordID.recordName, kind: kind, updatedAt: updatedAt, deleted: true,
                            contentHash: record["contentHash"] as? String ?? "", token: nil, settingKey: nil, setting: nil)
        }
        if kind == "token", let label = record.encryptedValues["label"] as? String,
           let account = record.encryptedValues["account"] as? String, let secret = record.encryptedValues["secret"] as? String,
           let algorithmRaw = record["algorithm"] as? String,
           let algorithm = OTPAlgorithm(rawValue: algorithmRaw),
           let digits = (record["digits"] as? NSNumber)?.intValue,
           let period = (record["period"] as? NSNumber)?.intValue {
            let token = deleted ? nil : OTPCode(id: UUID(uuidString: record.recordID.recordName) ?? UUID(),
                                                 label: label, account: account, secret: secret,
                                                 algorithm: algorithm, digits: digits, period: period,
                                                 timerRingHex: record["timerRingHex"] as? String)
            return SyncItem(key: record.recordID.recordName, kind: kind, updatedAt: updatedAt, deleted: deleted,
                            contentHash: record["contentHash"] as? String ?? token.map(tokenHash) ?? "", token: token, settingKey: nil, setting: nil)
        }
        if kind == "setting", let key = record["settingKey"] as? String {
            return SyncItem(key: record.recordID.recordName, kind: kind, updatedAt: updatedAt, deleted: deleted,
                            contentHash: record["contentHash"] as? String ?? settingHash((record["value"] as? NSNumber)?.boolValue ?? false),
                            token: nil, settingKey: key, setting: deleted ? nil : (record["value"] as? NSNumber)?.boolValue)
        }
        return nil
    }

    private func encode(_ item: SyncItem, into existing: CKRecord? = nil) -> CKRecord {
        let id = CKRecord.ID(recordName: item.key)
        let record = existing ?? CKRecord(recordType: Self.recordType, recordID: id)
        record["kind"] = item.kind as CKRecordValue
        record["updatedAt"] = item.updatedAt as CKRecordValue
        record["deleted"] = item.deleted as NSNumber
        record["contentHash"] = item.contentHash as CKRecordValue
        if item.kind == "token", let token = item.token {
            record.encryptedValues["label"] = token.label as CKRecordValue
            record.encryptedValues["account"] = token.account as CKRecordValue
            record.encryptedValues["secret"] = token.secret as CKRecordValue
            record["algorithm"] = token.algorithm.rawValue as CKRecordValue
            record["digits"] = token.digits as NSNumber
            record["period"] = token.period as NSNumber
            if let ring = token.timerRingHex { record["timerRingHex"] = ring as CKRecordValue }
        } else if item.kind == "setting", let settingKey = item.settingKey {
            record["settingKey"] = settingKey as CKRecordValue
            if let value = item.setting { record["value"] = value as NSNumber }
        }
        return record
    }

    private func tokenHash(_ token: OTPCode) -> String {
        (try? String(data: JSONEncoder().encode(token), encoding: .utf8)) ?? token.id.uuidString
    }

    private func settingHash(_ value: Bool) -> String { value ? "true" : "false" }
    private func settingRecordName(_ key: String) -> String { "setting.\(key)" }
    private func settingKey(for recordName: String) -> String? {
        guard recordName.hasPrefix("setting.") else { return nil }
        return String(recordName.dropFirst("setting.".count))
    }

    // MARK: - State and errors

    private func scheduleSync() {
        pendingWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async { self.syncNow(codes: self.currentCodes, settings: self.currentSettings) }
        }
        pendingWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func finish(codes: [OTPCode], settings: [String: Bool]) {
        isSyncInProgress = false
        defaults.set(Date(), forKey: Self.syncAnchorKey)
        updateStatus(.idle)
        onSyncCompleted?(CloudSyncResult(codes: codes, settings: settings))
    }

    private func finishWith(error: Error) {
        isSyncInProgress = false
        let cloudError = error as? CKError
        let normalizedMessage = error.localizedDescription.lowercased()
        if normalizedMessage.contains("did not find record type") ||
            normalizedMessage.contains("record type") && normalizedMessage.contains("not found") {
            updateStatus(.schemaUnavailable)
            return
        }
        switch cloudError?.code {
        case .notAuthenticated, .permissionFailure:
            updateStatus(.accountUnavailable)
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited:
            updateStatus(.offline)
        default:
            updateStatus(.error(Self.describe(error)))
        }
    }

    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        var message = error.localizedDescription
        if let cloudError = error as? CKError {
            message = "CloudKit \(cloudError.code.rawValue): \(message)"
            if cloudError.code == .partialFailure,
               let partialErrors = cloudError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error] {
                let details = partialErrors.map { key, itemError in
                    "\(key): \(itemError.localizedDescription)"
                }.sorted().joined(separator: "; ")
                if !details.isEmpty {
                    message += " [\(details)]"
                }
            }
            if let serverMessage = cloudError.userInfo["CKErrorServerMessage"] as? String,
               !serverMessage.isEmpty,
               serverMessage != message {
                message += " (\(serverMessage))"
            }
        } else if nsError.domain != "NSCocoaErrorDomain" {
            message = "\(nsError.domain) \(nsError.code): \(message)"
        }
        return message
    }

    private func updateStatus(_ newStatus: CloudSyncStatus) {
        status = newStatus
        DispatchQueue.main.async { [weak self] in self?.onStatusChange?(newStatus) }
    }

    private func persistMetadata() {
        if let data = try? JSONEncoder().encode(metadata) {
            defaults.set(data, forKey: Self.metadataKey)
        }
    }
}

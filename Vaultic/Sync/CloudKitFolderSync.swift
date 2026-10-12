import CloudKit
import Foundation

/// Syncs the folder list and which token sits in which folder.
///
/// The whole organization is one encrypted record. Folders are few and small, so one
/// record is simpler than one per folder, and it avoids a second set of delete
/// markers. The cost is that two devices editing folders at the same moment keep
/// only the later copy as a whole: that is the same last-write-wins rule the tokens
/// use, applied to the folder list.
@MainActor
protocol FolderSyncing: AnyObject {
    /// Compares this device's folders with iCloud and returns the copy to adopt, or
    /// `nil` when nothing needs to change on this device.
    func sync(local: TokenOrganization) async -> TokenOrganization?
}

/// The rule for choosing between this device's folders and the copy in iCloud.
///
/// Last write wins on the organization's timestamp. A copy that was never changed
/// (`nil`) loses to any copy that was. Equal timestamps mean the same copy.
nonisolated enum FolderSyncMerge {
    enum Decision: Equatable {
        case nothing
        case upload
        case adoptRemote
    }

    static func decide(localModifiedAt: Date?, remoteModifiedAt: Date?, remoteExists: Bool) -> Decision {
        guard remoteExists else {
            return localModifiedAt == nil ? .nothing : .upload
        }
        let local = localModifiedAt ?? .distantPast
        let remote = remoteModifiedAt ?? .distantPast
        if remote > local { return .adoptRemote }
        if local > remote { return .upload }
        return .nothing
    }
}

/// How the organization is stored in its CloudKit record.
nonisolated enum FolderRecordCodec {
    static let recordType = "AutherisFolders"
    static let recordName = "folders"
    /// End-to-end encrypted, like the token secrets: the folder names, colours and
    /// assignments are read and written only through `encryptedValues`.
    static let payloadField = "payload"

    static func encode(_ organization: TokenOrganization, into existing: CKRecord?) throws -> CKRecord {
        let record = existing ?? CKRecord(recordType: recordType,
                                          recordID: CKRecord.ID(recordName: recordName))
        let data = try JSONEncoder().encode(organization)
        record.encryptedValues[payloadField] = String(decoding: data, as: UTF8.self)
        return record
    }

    static func decode(_ record: CKRecord) -> TokenOrganization? {
        guard let text = record.encryptedValues[payloadField] as? String,
              let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(TokenOrganization.self, from: data)
    }
}

/// The CloudKit side of folder sync, in the user's private database.
@MainActor
final class CloudKitFolderSync: FolderSyncing {
    /// Tries a push at most this often. A second pass re-reads the server's copy
    /// after another device wrote first, so it decides against the current record.
    private static let maxAttempts = 2

    func sync(local: TokenOrganization) async -> TokenOrganization? {
        let database = CKContainer(identifier: CloudKitTokenSyncService.containerIdentifier).privateCloudDatabase
        var existing: CKRecord?
        do {
            for _ in 0..<Self.maxAttempts {
                existing = try await fetch(from: database)
                let remote = existing.flatMap(FolderRecordCodec.decode)
                let decision = FolderSyncMerge.decide(localModifiedAt: local.modifiedAt,
                                                     remoteModifiedAt: remote?.modifiedAt,
                                                     remoteExists: existing != nil)
                switch decision {
                case .nothing:
                    return nil
                case .adoptRemote:
                    return remote
                case .upload:
                    let record = try FolderRecordCodec.encode(local, into: existing)
                    let response = try await database.modifyRecords(
                        saving: [record],
                        deleting: [],
                        // Refused when the server's copy changed since it was read, so a
                        // stale device finds out instead of overwriting.
                        savePolicy: .ifServerRecordUnchanged,
                        atomically: true
                    )
                    guard case .failure(let error)? = response.saveResults[record.recordID] else {
                        return nil
                    }
                    // Another device wrote first. Read its copy and decide again.
                    guard let serverRecord = (error as? CKError)?.serverRecord else { return nil }
                    existing = serverRecord
                }
            }
        } catch {
            // A failure here leaves folders as they are on this device; the next sync
            // tries again, and it must not fail the token sync around it.
            return nil
        }
        return nil
    }

    private func fetch(from database: CKDatabase) async throws -> CKRecord? {
        do {
            return try await database.record(for: CKRecord.ID(recordName: FolderRecordCodec.recordName))
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }
}

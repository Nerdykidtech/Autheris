import XCTest
import CloudKit
@testable import Vaultic

/// What a push does when the server has moved on since the sync fetched it.
///
/// Uploads used `.changedKeys`, which compares no change tags, so a device
/// working from a stale fetch overwrote the newer copy and the conflict handling
/// below never ran. A fake database answers the way CloudKit does, so it can.
@MainActor
final class CloudKitPushTests: XCTestCase {

    private let id = UUID()

    private func token(_ label: String, at seconds: TimeInterval) -> OTPCode {
        OTPCode(id: id, label: label, account: "user", secret: "JBSWY3DPEHPK3PXP",
                modifiedAt: Date(timeIntervalSince1970: seconds))
    }

    private func conflict(_ serverRecord: CKRecord) -> CKError {
        CKError(.serverRecordChanged, userInfo: [CKRecordChangedErrorServerRecordKey: serverRecord])
    }

    // MARK: - Change tags

    func testAnUploadIsWrittenOntoTheFetchedRecordAndRefusedIfItChanged() async throws {
        let fetched = CloudKitTokenSyncService.encode(.live(token("Old", at: 1_000)))
        let database = FakeCloudDatabase()

        _ = try await CloudKitTokenSyncService.push([.live(token("New", at: 2_000))],
                                                    onto: [id.uuidString: fetched],
                                                    using: database)

        XCTAssertTrue(database.calls.first?.records.first === fetched,
                      "the fetched record carries the change tag that makes a conflict detectable")
        XCTAssertEqual(database.calls.first?.policy, .ifServerRecordUnchanged)
    }

    // MARK: - Conflicts

    func testWhenTheServerCopyIsNewerItIsAdoptedNotOverwritten() async throws {
        let serverRecord = CloudKitTokenSyncService.encode(.live(token("Theirs", at: 3_000)))
        let database = FakeCloudDatabase { records, _ in
            Dictionary(uniqueKeysWithValues: records.map { ($0.recordID, .failure(self.conflict(serverRecord))) })
        }

        let adopted = try await CloudKitTokenSyncService.push([.live(token("Ours", at: 2_000))],
                                                              onto: [:], using: database)

        XCTAssertEqual(adopted.map { $0.token?.label }, ["Theirs"])
        XCTAssertEqual(database.calls.count, 1, "a losing upload is not retried")
    }

    func testWhenOursIsNewerItIsRetriedOnTheServersRecord() async throws {
        let serverRecord = CloudKitTokenSyncService.encode(.live(token("Theirs", at: 1_000)))
        let database = FakeCloudDatabase { records, call in
            Dictionary(uniqueKeysWithValues: records.map {
                ($0.recordID, call == 1 ? .failure(self.conflict(serverRecord)) : .success($0))
            })
        }

        let adopted = try await CloudKitTokenSyncService.push([.live(token("Ours", at: 2_000))],
                                                              onto: [:], using: database)

        XCTAssertTrue(adopted.isEmpty)
        XCTAssertEqual(database.calls.count, 2)
        let retried = try XCTUnwrap(database.calls.last?.records.first)
        XCTAssertTrue(retried === serverRecord, "the retry must carry the server's current change tag")
        XCTAssertEqual(retried.encryptedValues[CloudKitTokenSyncService.Field.label] as? String, "Ours")
    }

    func testARetryNeverWritesALowerCounterOverAHigherOne() async throws {
        // Ours is the newer edit (a rename), but another device spent two codes
        // and wrote first. Last-write-wins alone would put the server back on 3.
        let ours = OTPCode(id: id, label: "Bank (personal)", account: "user", secret: "JBSWY3DPEHPK3PXP",
                           kind: .hotp, counter: 3, modifiedAt: Date(timeIntervalSince1970: 2_000))
        let theirs = OTPCode(id: id, label: "Bank", account: "user", secret: "JBSWY3DPEHPK3PXP",
                             kind: .hotp, counter: 5, modifiedAt: Date(timeIntervalSince1970: 1_000))
        let serverRecord = CloudKitTokenSyncService.encode(.live(theirs))
        let database = FakeCloudDatabase { records, call in
            Dictionary(uniqueKeysWithValues: records.map {
                ($0.recordID, call == 1 ? .failure(self.conflict(serverRecord)) : .success($0))
            })
        }

        let adopted = try await CloudKitTokenSyncService.push([.live(ours)], onto: [:], using: database)

        let retried = try XCTUnwrap(database.calls.last?.records.first)
        XCTAssertEqual(database.calls.count, 2)
        XCTAssertEqual((retried[CloudKitTokenSyncService.Field.counter] as? NSNumber)?.uint64Value, 5)
        XCTAssertEqual(retried.encryptedValues[CloudKitTokenSyncService.Field.label] as? String, "Bank (personal)")
        // This device holds counter 3, so the settled copy comes back to be applied.
        XCTAssertEqual(adopted.map { $0.token?.counter }, [5])
        XCTAssertEqual(adopted.map { $0.token?.label }, ["Bank (personal)"])
    }

    // MARK: - Tombstones

    func testATombstoneWrittenOntoTheFetchedRecordClearsItsSecrets() async throws {
        let fetched = CloudKitTokenSyncService.encode(.live(token("GitHub", at: 1_000)))
        let database = FakeCloudDatabase()

        _ = try await CloudKitTokenSyncService.push(
            [.tombstone(id: id.uuidString, deletedAt: Date(timeIntervalSince1970: 2_000))],
            onto: [id.uuidString: fetched], using: database)

        let saved = try XCTUnwrap(database.calls.first?.records.first)
        XCTAssertEqual((saved[CloudKitTokenSyncService.Field.deleted] as? NSNumber)?.boolValue, true)
        for key in CloudKitTokenSyncService.Field.encrypted {
            XCTAssertNil(saved.encryptedValues[key], "\(key) must not outlive the delete")
        }
    }

    func testTombstonesThatStillHoldSecretsAreScrubbed() async throws {
        // What an earlier version left: a tombstone over the old encrypted fields.
        let leftover = CloudKitTokenSyncService.encode(.live(token("GitHub", at: 1_000)))
        leftover[CloudKitTokenSyncService.Field.deleted] = NSNumber(value: true)
        let clean = CloudKitTokenSyncService.encode(.tombstone(id: UUID().uuidString, deletedAt: Date()))
        let database = FakeCloudDatabase()

        try await CloudKitTokenSyncService.scrubTombstones(in: [leftover, clean],
                                                           skipping: [],
                                                           using: database)

        XCTAssertEqual(database.calls.count, 1)
        let scrubbed = try XCTUnwrap(database.calls.first?.records)
        XCTAssertEqual(scrubbed.map(\.recordID), [leftover.recordID], "a clean tombstone needs no write")
        XCTAssertNil(leftover.encryptedValues[CloudKitTokenSyncService.Field.secret])
        XCTAssertEqual(database.calls.first?.policy, .ifServerRecordUnchanged)
    }

    func testARecordUploadedThisSyncIsNotScrubbedAgain() async throws {
        let leftover = CloudKitTokenSyncService.encode(.live(token("GitHub", at: 1_000)))
        leftover[CloudKitTokenSyncService.Field.deleted] = NSNumber(value: true)
        let database = FakeCloudDatabase()

        try await CloudKitTokenSyncService.scrubTombstones(in: [leftover],
                                                           skipping: [id.uuidString],
                                                           using: database)

        XCTAssertTrue(database.calls.isEmpty)
    }
}

/// Answers `modifyRecords` the way a test says, and remembers each call.
private final class FakeCloudDatabase: CloudRecordSaving, @unchecked Sendable {
    typealias Respond = ([CKRecord], Int) -> [CKRecord.ID: Result<CKRecord, any Error>]

    private(set) var calls: [(records: [CKRecord], policy: CKModifyRecordsOperation.RecordSavePolicy)] = []
    private let respond: Respond

    /// By default every record saves.
    init(respond: @escaping Respond = { records, _ in
        Dictionary(uniqueKeysWithValues: records.map { ($0.recordID, .success($0)) })
    }) {
        self.respond = respond
    }

    func modifyRecords(
        saving recordsToSave: [CKRecord],
        deleting recordIDsToDelete: [CKRecord.ID],
        savePolicy: CKModifyRecordsOperation.RecordSavePolicy,
        atomically: Bool
    ) async throws -> (saveResults: [CKRecord.ID: Result<CKRecord, any Error>],
                       deleteResults: [CKRecord.ID: Result<Void, any Error>]) {
        calls.append((recordsToSave, savePolicy))
        return (respond(recordsToSave, calls.count), [:])
    }
}

/// Which CloudKit errors count as "this record type doesn't exist yet", which a
/// fetch reads as "no records". Too loose, and a failed read looks like an empty
/// iCloud — so "Delete from iCloud" deletes nothing and says it worked.
@MainActor
final class CloudKitMissingRecordTypeTests: XCTestCase {

    func testTheServersOwnWordingCounts() {
        let error = CKError(.invalidArguments,
                            userInfo: [NSDebugDescriptionErrorKey: "Did not find record type: AutherisToken"])
        XCTAssertTrue(CloudKitTokenSyncService.isMissingRecordType(error))
    }

    func testAnUnknownItemCounts() {
        XCTAssertTrue(CloudKitTokenSyncService.isMissingRecordType(CKError(.unknownItem)))
    }

    func testAnErrorThatOnlyMentionsARecordTypeIsStillAFailure() {
        let error = CKError(.invalidArguments, userInfo: [
            NSDebugDescriptionErrorKey: "Field 'secret' is not valid for record type AutherisToken",
            NSUnderlyingErrorKey: NSError(domain: "CKInternalErrorDomain", code: 1009, userInfo: [
                NSDebugDescriptionErrorKey: "Rejected write to record type AutherisToken"
            ])
        ])
        XCTAssertFalse(CloudKitTokenSyncService.isMissingRecordType(error))
    }
}

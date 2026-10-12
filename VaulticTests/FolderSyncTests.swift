import CloudKit
import XCTest
@testable import Vaultic

/// The rule for choosing between this device's folders and iCloud's copy, the record
/// that carries them, and the store that stamps and adopts them.
final class FolderSyncTests: XCTestCase {

    private let earlier = Date(timeIntervalSince1970: 1_000)
    private let later = Date(timeIntervalSince1970: 2_000)

    // MARK: - The decision

    func testNoRemoteCopyUploadsAStampedLocalCopy() {
        XCTAssertEqual(FolderSyncMerge.decide(localModifiedAt: later, remoteModifiedAt: nil, remoteExists: false), .upload)
    }

    func testNoRemoteCopyAndNoLocalChangeDoesNothing() {
        XCTAssertEqual(FolderSyncMerge.decide(localModifiedAt: nil, remoteModifiedAt: nil, remoteExists: false), .nothing)
    }

    func testANewerRemoteCopyIsAdopted() {
        XCTAssertEqual(FolderSyncMerge.decide(localModifiedAt: earlier, remoteModifiedAt: later, remoteExists: true), .adoptRemote)
    }

    func testANewerLocalCopyIsUploaded() {
        XCTAssertEqual(FolderSyncMerge.decide(localModifiedAt: later, remoteModifiedAt: earlier, remoteExists: true), .upload)
    }

    func testAFreshDeviceAdoptsTheRemoteCopy() {
        XCTAssertEqual(FolderSyncMerge.decide(localModifiedAt: nil, remoteModifiedAt: earlier, remoteExists: true), .adoptRemote)
    }

    func testEqualStampsAreAlreadyTheSameCopy() {
        XCTAssertEqual(FolderSyncMerge.decide(localModifiedAt: later, remoteModifiedAt: later, remoteExists: true), .nothing)
    }

    // MARK: - The record

    func testOrganizationRoundTripsThroughTheRecord() throws {
        var organization = TokenOrganization()
        let folder = try XCTUnwrap(organization.addFolder(named: "Work", color: .orange))
        let code = OTPCode(label: "GitHub", account: "ada", secret: "JBSWY3DPEHPK3PXP")
        organization.setFolder(folder.id, for: code.id)
        organization.stamp(later)

        let record = try FolderRecordCodec.encode(organization, into: nil)
        XCTAssertEqual(record.recordType, FolderRecordCodec.recordType)
        XCTAssertEqual(record.recordID.recordName, FolderRecordCodec.recordName)
        XCTAssertEqual(FolderRecordCodec.decode(record), organization)
    }

    func testEncodingOntoAnExistingRecordKeepsItsRecordID() throws {
        let existing = CKRecord(recordType: FolderRecordCodec.recordType,
                                recordID: CKRecord.ID(recordName: FolderRecordCodec.recordName))
        let record = try FolderRecordCodec.encode(TokenOrganization(), into: existing)
        XCTAssertTrue(record === existing, "the server's record is reused, so its change tag carries over")
    }

    func testFolderNamesAreStoredEncryptedNotAsPlainFields() throws {
        var organization = TokenOrganization()
        _ = organization.addFolder(named: "Banking")
        let record = try FolderRecordCodec.encode(organization, into: nil)
        XCTAssertNil(record[FolderRecordCodec.payloadField], "the payload is only read through encryptedValues")
        XCTAssertNotNil(record.encryptedValues[FolderRecordCodec.payloadField])
    }

    // MARK: - Pruning

    func testEntriesForPermanentlyDeletedTokensAreDropped() throws {
        var organization = TokenOrganization()
        let folder = try XCTUnwrap(organization.addFolder(named: "Work"))
        let kept = OTPCode(label: "Kept", account: "a", secret: "JBSWY3DPEHPK3PXP")
        let gone = OTPCode(label: "Gone", account: "b", secret: "JBSWY3DPEHPK3PXP")
        organization.setFolder(folder.id, for: kept.id)
        organization.setFolder(folder.id, for: gone.id)

        let pruned = organization.removingEntries(forTokens: [gone.id])

        XCTAssertEqual(pruned.folderByToken.keys.sorted { $0.uuidString < $1.uuidString }, [kept.id])
        XCTAssertEqual(pruned.modifiedAt, organization.modifiedAt, "pruning keeps the timestamp")
    }

    // MARK: - Saved data from before syncing

    func testAnOrganizationSavedWithoutATimestampStillLoads() throws {
        let json = #"{"folders":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Work"}],"folderByToken":[]}"#
        let decoded = try JSONDecoder().decode(TokenOrganization.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.folders.map(\.name), ["Work"])
        XCTAssertNil(decoded.modifiedAt, "a copy from before syncing never loses to a stamped one by accident")
    }

    func testAFolderSavedBeforeColoursLoadsWithNoColour() throws {
        let json = #"{"folders":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Work"}],"folderByToken":[]}"#
        let decoded = try JSONDecoder().decode(TokenOrganization.self, from: Data(json.utf8))
        XCTAssertNil(decoded.folders.first?.color)
    }

    // MARK: - The store

    @MainActor
    func testALocalChangeIsStampedSavedAndReportedForSync() async throws {
        let suite = "FolderSyncTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = TokenOrganizationStore(defaults: defaults)
        var reported = 0
        store.onLocalChange = { reported += 1 }

        store.update { _ = $0.addFolder(named: "Work") }

        XCTAssertNotNil(store.organization.modifiedAt)
        XCTAssertEqual(reported, 1)
        XCTAssertEqual(TokenOrganizationStore(defaults: defaults).organization.folders.map(\.name), ["Work"])
    }

    @MainActor
    func testAChangeThatChangesNothingIsNotStampedOrReported() async throws {
        let suite = "FolderSyncTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = TokenOrganizationStore(defaults: defaults)
        var reported = 0
        store.onLocalChange = { reported += 1 }

        store.update { _ in }

        XCTAssertNil(store.organization.modifiedAt)
        XCTAssertEqual(reported, 0)
    }

    @MainActor
    func testAnAdoptedCopyKeepsItsTimestampAndIsNotReportedBack() async throws {
        let suite = "FolderSyncTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        var remote = TokenOrganization()
        _ = remote.addFolder(named: "Shared")
        remote.stamp(later)

        let store = TokenOrganizationStore(defaults: defaults)
        var reported = 0
        store.onLocalChange = { reported += 1 }

        store.adoptRemote(remote)

        XCTAssertEqual(store.organization.folders.map(\.name), ["Shared"])
        XCTAssertEqual(store.organization.modifiedAt, later)
        XCTAssertEqual(reported, 0, "an adopted copy is not sent straight back")
    }
}

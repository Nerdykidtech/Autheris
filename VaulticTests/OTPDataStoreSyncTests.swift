import XCTest
import Security
@testable import Vaultic

/// How `OTPDataStore` folds a sync result back into its own state.
///
/// `SyncMergeEngineTests` covers the merge itself; these cover what happens
/// after it, including edits that land while a sync is in flight. A fake
/// `TokenSyncService` stands in for CloudKit and can run code mid-sync.
@MainActor
final class OTPDataStoreSyncTests: XCTestCase {

    /// Everything the store reads or writes on init, so each test starts empty
    /// and the simulator's real data is put back afterwards.
    private let keychainAccounts = ["otpCodes", "otpSyncTombstones", "otpTrash", "appPreferences"]
    private var savedKeychain: [String: Data?] = [:]
    private var savedSyncEnabled: Any?

    private var sync: FakeTokenSyncService!
    private var store: OTPDataStore!

    override func setUp() async throws {
        try await super.setUp()
        for account in keychainAccounts {
            savedKeychain[account] = KeychainStore.load(account: account)
            deleteKeychainItem(account: account)
        }
        savedSyncEnabled = UserDefaults.standard.object(forKey: OTPDataStore.syncEnabledKey)
        UserDefaults.standard.set(false, forKey: OTPDataStore.syncEnabledKey)

        sync = FakeTokenSyncService()
        store = OTPDataStore(syncService: sync, watchRelay: DisabledWatchTokenRelay())
        store.setSyncEnabled(true)
        // Turning sync on kicks off a sync of its own. Let it finish (the fake
        // has no handler yet, so it is a no-op) so it can't overlap a test's sync.
        while sync.syncCallCount == 0 { await Task.yield() }
    }

    override func tearDown() async throws {
        sync.handler = nil
        store = nil
        sync = nil
        for (account, data) in savedKeychain {
            if let data {
                _ = KeychainStore.save(data, account: account)
            } else {
                deleteKeychainItem(account: account)
            }
        }
        UserDefaults.standard.set(savedSyncEnabled, forKey: OTPDataStore.syncEnabledKey)
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func token(_ label: String) -> OTPCode {
        OTPCode(label: label, account: "user", secret: "JBSWY3DPEHPK3PXP")
    }

    /// Runs one sync and returns the snapshot the store handed to it.
    @discardableResult
    private func runSync(
        returning outcome: @escaping (SyncLocalState) -> SyncMergeOutcome?
    ) async -> SyncLocalState? {
        var captured: SyncLocalState?
        sync.handler = { local in
            captured = local
            return outcome(local)
        }
        await store.syncNow()
        sync.handler = nil
        return captured
    }

    private func deleteKeychainItem(account: String) {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.eddingtontech.autheris",
            kSecAttrAccount as String: account
        ]
        #if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Remote deletions

    func testARemoteTombstoneRemovesTheTokenAndStaysRemoved() async {
        let doomed = token("GitHub")
        let kept = token("GitLab")
        store.addCode(doomed)
        store.addCode(kept)
        let deletedAt = Date()

        await runSync { _ in
            SyncMergeOutcome(tokens: [kept],
                             tombstones: [doomed.id.uuidString: deletedAt],
                             uploads: [],
                             didAdoptRemoteChanges: true)
        }

        XCTAssertEqual(store.codes.map(\.id), [kept.id])

        // The next sync must not offer the deleted token back to the merge.
        let next = await runSync { _ in nil }
        XCTAssertEqual(next?.tokens.map(\.id), [kept.id])
        XCTAssertEqual(next?.tombstones[doomed.id.uuidString], deletedAt)
    }

    // MARK: - Local edits while a sync is in flight

    func testATokenDeletedMidSyncStaysDeleted() async {
        let doomed = token("GitHub")
        let kept = token("GitLab")
        let remote = token("Bitbucket")
        store.addCode(doomed)
        store.addCode(kept)

        await runSync { [store] local in
            store!.removeCode(doomed)
            // The merge only saw the snapshot, so it still lists the token.
            return SyncMergeOutcome(tokens: local.tokens + [remote],
                                    tombstones: local.tombstones,
                                    uploads: [],
                                    didAdoptRemoteChanges: true)
        }

        XCTAssertEqual(Set(store.codes.map(\.id)), [kept.id, remote.id])
        let next = await runSync { _ in nil }
        XCTAssertNotNil(next?.tombstones[doomed.id.uuidString],
                        "The local deletion must still be waiting to propagate")
    }

    func testATokenAddedMidSyncIsKept() async {
        let existing = token("GitHub")
        let added = token("GitLab")
        let remote = token("Bitbucket")
        store.addCode(existing)

        await runSync { [store] local in
            store!.addCode(added)
            return SyncMergeOutcome(tokens: local.tokens + [remote],
                                    tombstones: local.tombstones,
                                    uploads: [],
                                    didAdoptRemoteChanges: true)
        }

        XCTAssertEqual(Set(store.codes.map(\.id)), [existing.id, added.id, remote.id])
    }

    func testATokenRestoredMidSyncLosesItsTombstone() async throws {
        let restored = token("GitHub")
        store.addCode(restored)
        store.removeCode(restored)
        let entry = try XCTUnwrap(store.trash.first)

        await runSync { [store] local in
            XCTAssertNotNil(local.tombstones[restored.id.uuidString])
            store!.restoreFromTrash(entry)
            return SyncMergeOutcome(tokens: local.tokens,
                                    tombstones: local.tombstones,
                                    uploads: [],
                                    didAdoptRemoteChanges: true)
        }

        XCTAssertEqual(store.codes.map(\.id), [restored.id])
        let next = await runSync { _ in nil }
        XCTAssertNil(next?.tombstones[restored.id.uuidString],
                     "A stale tombstone would delete the restored token on the next sync")
    }

    // MARK: - Restoring a backup

    func testATokenRestoredFromABackupSurvivesTheTombstoneItsDeleteLeftInICloud() async throws {
        // Made an hour ago, backed up, then deleted — so iCloud holds a tombstone
        // newer than the copy in the backup.
        let restored = OTPCode(label: "GitHub", account: "user", secret: "JBSWY3DPEHPK3PXP",
                               modifiedAt: Date(timeIntervalSinceNow: -3600))
        store.addCode(restored)
        let backup = try BackupCrypto.encrypt(plaintext: try JSONEncoder().encode([restored]),
                                              password: "correct horse battery staple")
        store.removeCode(restored)
        let remoteTombstone = SyncRecord.tombstone(id: restored.id.uuidString, deletedAt: Date())

        XCTAssertTrue(store.restoreFromBackup(backup, isEncrypted: true,
                                              password: "correct horse battery staple"))
        await runSync { local in
            SyncMergeEngine.merge(local: local, remote: [remoteTombstone], now: Date(),
                                  tombstoneRetention: SyncMergeEngine.defaultTombstoneRetention)
        }

        XCTAssertEqual(store.codes.map(\.id), [restored.id])
    }

    // MARK: - Importing

    func testImportedCodesGetANewIDAndAFreshTimestamp() {
        let existing = token("GitHub")
        store.addCode(existing)
        // Reuses an id already in the vault and claims to be from next year.
        let hostile = OTPCode(id: existing.id, label: "GitLab", account: "user",
                              secret: "JBSWY3DPEHPK3PXP",
                              modifiedAt: Date(timeIntervalSinceNow: 365 * 24 * 3600))

        let result = store.addCodes([hostile])

        XCTAssertEqual(result.added, 1)
        XCTAssertEqual(result.skipped, 0)
        let imported = store.codes.first { $0.label == "GitLab" }
        XCTAssertNotNil(imported)
        XCTAssertNotEqual(imported?.id, existing.id)
        XCTAssertLessThanOrEqual(imported?.modifiedAt ?? .distantFuture, Date())
        XCTAssertEqual(store.codes.first { $0.label == "GitHub" }?.id, existing.id,
                       "the code already in the vault must be left alone")
    }

    func testImportCountsOnlyTheCodesThatWereActuallyAdded() {
        store.addCode(token("GitHub"))

        let result = store.addCodes([
            token("GitHub"),    // already in the vault
            token("GitLab"),
            token("GitLab"),    // repeated within the payload
            OTPCode(label: "GitHub ", account: "user", secret: "JBSWY3DPEHPK3PXP"),
        ])

        XCTAssertEqual(result.added, 2)
        XCTAssertEqual(result.skipped, 2)
        XCTAssertEqual(store.codes.map(\.label).sorted(), ["GitHub", "GitHub ", "GitLab"])
    }

    // MARK: - Overlapping syncs

    func testAnEditDuringASyncIsSyncedAsSoonAsItFinishes() async {
        let existing = token("GitHub")
        let added = token("GitLab")
        store.addCode(existing)
        var snapshots: [SyncLocalState] = []
        sync.handler = { [store] local in
            snapshots.append(local)
            if snapshots.count == 1 {
                // An edit lands mid-sync and asks for a sync of its own.
                store!.addCode(added)
                await store!.syncNow()
            }
            return SyncMergeOutcome(tokens: local.tokens, tombstones: local.tombstones,
                                    uploads: [], didAdoptRemoteChanges: false)
        }

        await store.syncNow()
        sync.handler = nil

        XCTAssertEqual(snapshots.count, 2, "the sync requested mid-sync must run, once")
        XCTAssertEqual(Set(snapshots.last?.tokens.map(\.id) ?? []), [existing.id, added.id])
    }
}

/// A `TokenSyncService` whose `sync(local:)` result each test supplies.
@MainActor
private final class FakeTokenSyncService: TokenSyncService {
    var isEnabled = false
    var status: CloudSyncStatus = .disabled
    var isAvailable = true
    var onStatusChange: ((CloudSyncStatus) -> Void)?

    var handler: ((SyncLocalState) async -> SyncMergeOutcome?)?
    private(set) var syncCallCount = 0

    func refreshAvailability() async {}
    func setEnabled(_ enabled: Bool) { isEnabled = enabled }

    /// Refuses to overlap, like `CloudKitTokenSyncService`.
    private var isSyncing = false

    func sync(local: SyncLocalState) async -> SyncMergeOutcome? {
        guard !isSyncing else { return nil }
        isSyncing = true
        defer { isSyncing = false }
        syncCallCount += 1
        return await handler?(local)
    }

    func deleteRemoteRecords() async throws {}
    func handleRemoteNotification(userInfo: [AnyHashable: Any]) -> Bool { false }
}

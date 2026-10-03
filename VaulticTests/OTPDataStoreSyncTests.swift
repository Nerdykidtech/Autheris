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

        store.replaceAll(with: try await OTPDataStore.readBackup(backup, isEncrypted: true,
                                                                 password: "correct horse battery staple"))
        await runSync { local in
            SyncMergeEngine.merge(local: local, remote: [remoteTombstone], now: Date(),
                                  tombstoneRetention: SyncMergeEngine.defaultTombstoneRetention)
        }

        XCTAssertEqual(store.codes.map(\.id), [restored.id])
    }

    // MARK: - Importing

    func testImportedCodesGetANewIDAndAFreshTimestamp() throws {
        let existing = token("GitHub")
        store.addCode(existing)
        // Reuses an id already in the vault and claims to be from next year.
        let hostile = OTPCode(id: existing.id, label: "GitLab", account: "user",
                              secret: "JBSWY3DPEHPK3PXP",
                              modifiedAt: Date(timeIntervalSinceNow: 365 * 24 * 3600))

        let result = try XCTUnwrap(store.addCodes([hostile]))

        XCTAssertEqual(result.added, 1)
        XCTAssertEqual(result.skipped, 0)
        let imported = store.codes.first { $0.label == "GitLab" }
        XCTAssertNotNil(imported)
        XCTAssertNotEqual(imported?.id, existing.id)
        XCTAssertLessThanOrEqual(imported?.modifiedAt ?? .distantFuture, Date())
        XCTAssertEqual(store.codes.first { $0.label == "GitHub" }?.id, existing.id,
                       "the code already in the vault must be left alone")
    }

    func testImportCountsOnlyTheCodesThatWereActuallyAdded() throws {
        store.addCode(token("GitHub"))

        let result = try XCTUnwrap(store.addCodes([
            token("GitHub"),    // already in the vault
            token("GitLab"),
            token("GitLab"),    // repeated within the payload
            OTPCode(label: "GitHub ", account: "user", secret: "JBSWY3DPEHPK3PXP"),
        ]))

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

    // MARK: - Codes that share a name

    func testTwoCodesThatOnlyShareANameAreBothSavedAndShown() throws {
        // Two different secrets under one name — what arrives when two devices
        // each added a different account under the same label. Saving used to keep
        // only the first, which lost the other secret for good.
        let first = OTPCode(label: "GitHub", account: "user", secret: "JBSWY3DPEHPK3PXP")
        let second = OTPCode(label: "github", account: "User", secret: "JBSWY3DPEHPK3PXQ")
        store.codes = [first, second]
        store.saveCodes()

        let saved = try JSONDecoder().decode([OTPCode].self,
                                             from: try XCTUnwrap(KeychainStore.load(account: "otpCodes")))
        XCTAssertEqual(saved.map(\.id), [first.id, second.id])
        XCTAssertEqual(Set(store.orderedCodes.map(\.id)), [first.id, second.id])

        let reloaded = OTPDataStore(syncService: FakeTokenSyncService(), watchRelay: DisabledWatchTokenRelay())
        XCTAssertEqual(reloaded.codes.map(\.id), [first.id, second.id])
    }

    func testCopiesAreShownOnceAndDeletedTogetherButANameSakeIsLeftAlone() {
        let original = OTPCode(label: "GitHub", account: "user", secret: "JBSWY3DPEHPK3PXP")
        let copy = OTPCode(label: "GitHub", account: "user", secret: "jbsw y3dp ehpk 3pxp")
        let namesake = OTPCode(label: "GitHub", account: "user", secret: "JBSWY3DPEHPK3PXQ")
        store.codes = [original, copy, namesake]

        XCTAssertEqual(Set(store.orderedCodes.map(\.id)), [original.id, namesake.id])

        store.removeCode(original)

        XCTAssertEqual(store.codes.map(\.id), [namesake.id])
        XCTAssertEqual(Set(store.trash.map(\.code.id)), [original.id, copy.id])
    }

    func testARenameOntoAnotherCodesNameIsRefused() throws {
        let work = OTPCode(label: "GitHub", account: "work", secret: "JBSWY3DPEHPK3PXP")
        let personal = OTPCode(label: "GitHub", account: "personal", secret: "JBSWY3DPEHPK3PXQ")
        store.addCode(work)
        store.addCode(personal)
        let index = try XCTUnwrap(store.codes.firstIndex { $0.id == work.id })
        let renamed = work.edited(account: "Personal")

        XCTAssertTrue(store.nameIsTaken(by: renamed))
        XCTAssertFalse(store.updateCode(renamed, at: index))
        XCTAssertEqual(store.codes.first { $0.id == work.id }?.account, "work")

        // Renaming a code to its own name, in another case, is not a clash.
        XCTAssertTrue(store.updateCode(work.edited(account: "Work"), at: index))
    }

    func testAddingACodeThatIsAlreadyHereReportsIt() {
        XCTAssertTrue(store.addCode(OTPCode(label: "GitHub", account: "alice", secret: "JBSWY3DPEHPK3PXP")))
        XCTAssertFalse(store.addCode(OTPCode(label: "github", account: "Alice", secret: "JBSWY3DPEHPK3PXQ")),
                       "a name that differs only in case is the same name")
        XCTAssertEqual(store.codes.count, 1)
    }

    // MARK: - Restoring a backup, continued

    func testRestoringABackupSendsTheCodesItReplacesToRecentlyDeleted() async throws {
        let kept = token("GitHub")
        let replaced = token("GitLab")
        store.addCode(kept)
        store.addCode(replaced)
        let backup = try BackupCrypto.encrypt(plaintext: try JSONEncoder().encode([kept]),
                                              password: "correct horse battery staple")

        store.replaceAll(with: try await OTPDataStore.readBackup(backup, isEncrypted: true,
                                                                 password: "correct horse battery staple"))

        XCTAssertEqual(store.codes.map(\.id), [kept.id])
        XCTAssertEqual(store.trash.map(\.code.id), [replaced.id])
        let next = await runSync { _ in nil }
        XCTAssertNotNil(next?.tombstones[replaced.id.uuidString],
                        "the replaced code still has to be deleted on the other devices")
    }

    func testReadingAnEncryptedBackupWithTheWrongPasswordChangesNothing() async throws {
        let existing = token("GitHub")
        store.addCode(existing)
        let backup = try BackupCrypto.encrypt(plaintext: try JSONEncoder().encode([token("GitLab")]),
                                              password: "correct horse battery staple")

        do {
            _ = try await OTPDataStore.readBackup(backup, isEncrypted: true, password: "wrong password!")
            XCTFail("a wrong password must not read the backup")
        } catch {}
        XCTAssertEqual(store.codes.map(\.id), [existing.id])
    }

    // MARK: - A vault that can't be read

    func testAVaultThatWontDecodeIsLeftAloneAndEditsAreRefused() {
        // Present but unreadable — corruption, or a field from a newer build. The
        // first edit used to save `[]` over it.
        let stored = Data("not a list of codes".utf8)
        XCTAssertTrue(KeychainStore.save(stored, account: "otpCodes"))

        let unreadable = OTPDataStore(syncService: FakeTokenSyncService(), watchRelay: DisabledWatchTokenRelay())

        XCTAssertFalse(unreadable.isVaultLoaded)
        XCTAssertTrue(unreadable.hasUnreadableCodes)
        XCTAssertFalse(unreadable.addCode(token("GitHub")), "an edit must not look saved when it can't be")
        XCTAssertNil(unreadable.addCodes([token("GitLab")]),
                     "a refused import must not read as \"all duplicates\"")
        XCTAssertFalse(unreadable.replaceAll(with: [token("GitLab")]),
                       "a refused restore must not read as restored")
        XCTAssertTrue(unreadable.codes.isEmpty)
        XCTAssertEqual(KeychainStore.load(account: "otpCodes"), stored)
    }

    func testUnreadableCodesCanBeSetAsideToStartOver() throws {
        let stored = Data("not a list of codes".utf8)
        XCTAssertTrue(KeychainStore.save(stored, account: "otpCodes"))
        let unreadable = OTPDataStore(syncService: FakeTokenSyncService(), watchRelay: DisabledWatchTokenRelay())
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let setAsideAccount = "otpCodes.unreadable.1800000000"
        defer { deleteKeychainItem(account: setAsideAccount) }

        XCTAssertTrue(unreadable.setAsideUnreadableCodes(now: now))

        XCTAssertEqual(KeychainStore.load(account: setAsideAccount), stored,
                       "the unreadable codes are kept, not thrown away")
        XCTAssertTrue(unreadable.isVaultLoaded)
        XCTAssertFalse(unreadable.hasUnreadableCodes)
        XCTAssertTrue(unreadable.addCode(token("GitHub")), "the vault works again")
        let saved = try JSONDecoder().decode([OTPCode].self,
                                             from: try XCTUnwrap(KeychainStore.load(account: "otpCodes")))
        XCTAssertEqual(saved.map(\.label), ["GitHub"])
    }

    func testALockedVaultIsNeverSetAside() {
        // Locked is not unreadable: it sorts itself out, and setting codes aside
        // then would start over for nothing.
        let locked = OTPDataStore(syncService: FakeTokenSyncService(), watchRelay: DisabledWatchTokenRelay()) { _ in
            .unavailable(errSecInteractionNotAllowed)
        }

        XCTAssertFalse(locked.hasUnreadableCodes)
        XCTAssertFalse(locked.setAsideUnreadableCodes())
        XCTAssertFalse(locked.isVaultLoaded)
    }

    func testNoSyncRunsWhileTheTombstonesCantBeRead() async throws {
        XCTAssertTrue(KeychainStore.save(try JSONEncoder().encode([token("GitHub")]), account: "otpCodes"))
        let partialSync = FakeTokenSyncService()
        let partial = OTPDataStore(syncService: partialSync, watchRelay: DisabledWatchTokenRelay()) { account in
            account == "otpSyncTombstones" ? .unavailable(errSecDecode) : KeychainStore.read(account: account)
        }
        XCTAssertTrue(partial.isVaultLoaded)

        partial.setSyncEnabled(true)
        await partial.syncNow()

        XCTAssertEqual(partialSync.syncCallCount, 0,
                       "without its tombstones, a local delete would look like a code to bring back")
    }

    func testAnUnreadableTrashDoesNotHoldUpTheCodesAndIsNotWrittenOver() throws {
        let existing = token("GitHub")
        XCTAssertTrue(KeychainStore.save(try JSONEncoder().encode([existing]), account: "otpCodes"))
        let storedTrash = Data("whatever the trash still holds".utf8)
        XCTAssertTrue(KeychainStore.save(storedTrash, account: "otpTrash"))

        let partial = OTPDataStore(syncService: FakeTokenSyncService(), watchRelay: DisabledWatchTokenRelay()) { account in
            account == "otpTrash" ? .unavailable(errSecDecode) : KeychainStore.read(account: account)
        }

        XCTAssertTrue(partial.isVaultLoaded, "a damaged trash must not keep anyone from their codes")
        XCTAssertEqual(partial.codes.map(\.id), [existing.id])

        partial.removeCode(existing)

        XCTAssertTrue(partial.codes.isEmpty)
        XCTAssertEqual(KeychainStore.load(account: "otpTrash"), storedTrash,
                       "an item that couldn't be read must not be replaced")
    }

    func testDraggingKeepsTheCopiesTheListHides() {
        let first = token("GitHub")
        let copy = OTPCode(label: "GitHub", account: "user", secret: "JBSWY3DPEHPK3PXP")
        let second = token("GitLab")
        store.codes = [first, copy, second]
        XCTAssertEqual(store.orderedCodes.map(\.id), [first.id, second.id])

        store.move(offsets: IndexSet(integer: 1), destination: 0)

        XCTAssertEqual(store.orderedCodes.map(\.id), [second.id, first.id])
        XCTAssertTrue(store.codes.contains { $0.id == copy.id },
                      "dropping a hidden copy is a delete with no tombstone")
    }

    // MARK: - Launching while the device is locked

    func testALaunchThatCannotReadTheKeychainLeavesTheVaultAloneUntilItCan() async throws {
        let existing = token("GitHub")
        let stored = try JSONEncoder().encode([existing])
        XCTAssertTrue(KeychainStore.save(stored, account: "otpCodes"))

        // What a silent push sees on a locked phone: every `WhenUnlocked` read
        // fails with errSecInteractionNotAllowed.
        let device = DeviceLockState()
        let relay = RecordingWatchTokenRelay()
        let lockedSync = FakeTokenSyncService()
        let locked = OTPDataStore(syncService: lockedSync, watchRelay: relay) { account in
            device.isLocked ? .unavailable(errSecInteractionNotAllowed) : KeychainStore.read(account: account)
        }

        XCTAssertFalse(locked.isVaultLoaded)
        XCTAssertTrue(locked.codes.isEmpty)
        XCTAssertTrue(relay.pushes.isEmpty, "an empty push would clear the watch's cache")

        locked.setSyncEnabled(true)
        await locked.syncNow()
        XCTAssertEqual(lockedSync.syncCallCount, 0, "an unloaded vault must not be merged with iCloud")

        locked.addCode(token("GitLab"))
        XCTAssertEqual(KeychainStore.load(account: "otpCodes"), stored,
                       "a save before the vault loads would overwrite it")

        // Unlocking the device retries the load.
        device.isLocked = false
        for name in AppActivity.keychainMayHaveBecomeReadable {
            NotificationCenter.default.post(name: name, object: nil)
        }
        for _ in 0..<100 where !locked.isVaultLoaded { await Task.yield() }

        XCTAssertTrue(locked.isVaultLoaded)
        XCTAssertEqual(locked.codes.map(\.id), [existing.id])
        XCTAssertEqual(relay.pushes.last?.map(\.id), [existing.id])
        XCTAssertEqual(KeychainStore.load(account: "otpCodes"), stored)
    }
}

/// Whether the simulated device is locked, shared with the store's Keychain reader.
@MainActor
private final class DeviceLockState {
    var isLocked = true
}

/// Records what the store offers the watch.
private final class RecordingWatchTokenRelay: WatchTokenRelayService {
    private(set) var pushes: [[OTPCode]] = []
    func push(_ tokens: [OTPCode]) { pushes.append(tokens) }
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

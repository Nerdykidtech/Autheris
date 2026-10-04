import XCTest
import Security
@testable import Vaultic

/// How `OTPDataStore` folds a sync result back into its own state.
///
/// `SyncMergeEngineTests` covers the merge itself; these cover what happens
/// after it, including edits that land while a sync is in flight. A fake
/// `TokenSyncService` stands in for CloudKit and can run code mid-sync.
///
/// A test that makes and drops its own store is `async` even when it awaits
/// nothing. On iOS 26, freeing a main-actor object inside a synchronous test
/// method crashes the Swift runtime (`swift_task_deinitOnExecutor` frees a
/// task-local scope it never allocated); the same release inside a task is fine.
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
        await waitUntil { self.sync.syncCallCount > 0 }
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

    /// Waits for `condition`, failing the test after `timeout` rather than
    /// hanging until xcodebuild gives up on the whole run.
    private func waitUntil(timeout: Duration = .seconds(5),
                           file: StaticString = #filePath, line: UInt = #line,
                           _ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else {
                return XCTFail("timed out waiting", file: file, line: line)
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
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

    func testATokenEditedMidSyncKeepsTheEdit() async {
        let counterBased = OTPCode(label: "Bank", account: "user", secret: "JBSWY3DPEHPK3PXP",
                                   kind: .hotp, counter: 3, modifiedAt: Date().addingTimeInterval(-60))
        let renamed = token("GitHub")
        let remote = token("Bitbucket")
        store.addCode(counterBased)
        store.addCode(renamed)

        await runSync { [store] local in
            // Spent a code and renamed another while the sync was out.
            store!.advanceCounter(for: counterBased)
            if let index = store!.codes.firstIndex(where: { $0.id == renamed.id }) {
                store!.updateCode(renamed.edited(label: "GitHub Work"), at: index)
            }
            // Remote changes came back, so the store rebuilds its list from the
            // snapshot — which predates both edits.
            return SyncMergeOutcome(tokens: local.tokens + [remote],
                                    tombstones: local.tombstones,
                                    uploads: [],
                                    didAdoptRemoteChanges: true)
        }

        let codes = Dictionary(uniqueKeysWithValues: store.codes.map { ($0.id, $0) })
        XCTAssertEqual(codes[counterBased.id]?.counter, 4, "a spent code must not come back")
        XCTAssertEqual(codes[renamed.id]?.label, "GitHub Work")
        XCTAssertNotNil(codes[remote.id], "the remote change is still applied")

        let next = await runSync { _ in nil }
        let uploaded = Dictionary(uniqueKeysWithValues: (next?.tokens ?? []).map { ($0.id, $0) })
        XCTAssertEqual(uploaded[counterBased.id]?.counter, 4, "and the next sync offers the edit up")
    }

    func testACodeSpentMidSyncIsNotUndoneByANewerCopyWithALowerCounter() async {
        let counterBased = OTPCode(label: "Bank", account: "user", secret: "JBSWY3DPEHPK3PXP",
                                   kind: .hotp, counter: 3, modifiedAt: Date().addingTimeInterval(-60))
        store.addCode(counterBased)

        await runSync { [store] local in
            // Two codes spent while the sync was out: 3 → 5.
            store!.advanceCounter(for: counterBased)
            store!.advanceCounter(for: counterBased)
            // The sync comes back with a copy stamped after both taps, that a
            // merge settled on counter 4.
            let settled = counterBased.edited(label: "Bank (personal)", counter: 4,
                                              modifiedAt: Date().addingTimeInterval(1))
            return SyncMergeOutcome(tokens: [settled], tombstones: local.tombstones,
                                    uploads: [], didAdoptRemoteChanges: true)
        }

        let code = store.codes.first { $0.id == counterBased.id }
        XCTAssertEqual(code?.label, "Bank (personal)", "the newer copy still wins")
        XCTAssertEqual(code?.counter, 5, "but not the counter")
    }

    func testARenameMidSyncKeepsACounterTheSyncMovedOn() async {
        let counterBased = OTPCode(label: "Bank", account: "user", secret: "JBSWY3DPEHPK3PXP",
                                   kind: .hotp, counter: 3, modifiedAt: Date().addingTimeInterval(-60))
        store.addCode(counterBased)

        await runSync { [store] local in
            // Renamed here while the sync was out...
            if let index = store!.codes.firstIndex(where: { $0.id == counterBased.id }) {
                store!.updateCode(store!.codes[index].edited(label: "Bank (personal)"), at: index)
            }
            // ...and it comes back with another device's copy, which spent 3 and 4.
            let spentElsewhere = counterBased.edited(counter: 5, modifiedAt: Date().addingTimeInterval(-30))
            return SyncMergeOutcome(tokens: [spentElsewhere], tombstones: local.tombstones,
                                    uploads: [], didAdoptRemoteChanges: true)
        }

        let code = store.codes.first { $0.id == counterBased.id }
        XCTAssertEqual(code?.label, "Bank (personal)", "the edit is kept")
        XCTAssertEqual(code?.counter, 5, "but the counter never goes back")

        let next = await runSync { _ in nil }
        let uploaded = next?.tokens.first { $0.id == counterBased.id }
        XCTAssertEqual(uploaded?.label, "Bank (personal)", "and the next sync offers both up")
        XCTAssertEqual(uploaded?.counter, 5)
    }

    func testARenameMidSyncSurvivesACounterConflictTheMergeSettled() async {
        let counterBased = OTPCode(label: "Bank", account: "user", secret: "JBSWY3DPEHPK3PXP",
                                   kind: .hotp, counter: 3, modifiedAt: Date().addingTimeInterval(-60))
        store.addCode(counterBased)
        // Another device spent codes earlier, but this device's copy is newer:
        // the merge keeps ours with that device's counter, as a new write.
        let remote = SyncRecord.live(counterBased.edited(counter: 5, modifiedAt: Date().addingTimeInterval(-120)))

        await runSync { [store] local in
            // Renamed here while the sync was still fetching, before the merge ran.
            if let index = store!.codes.firstIndex(where: { $0.id == counterBased.id }) {
                store!.updateCode(store!.codes[index].edited(label: "Bank (personal)"), at: index)
            }
            return SyncMergeEngine.merge(local: local, remote: [remote])
        }

        let code = store.codes.first { $0.id == counterBased.id }
        XCTAssertEqual(code?.label, "Bank (personal)", "the merged copy must not undo the rename")
        XCTAssertEqual(code?.counter, 5)
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

    func testImportedCodesGetANewIDAndAFreshTimestamp() {
        let existing = token("GitHub")
        store.addCode(existing)
        // Reuses an id already in the vault and claims to be from next year.
        let hostile = OTPCode(id: existing.id, label: "GitLab", account: "user",
                              secret: "JBSWY3DPEHPK3PXP",
                              modifiedAt: Date(timeIntervalSinceNow: 365 * 24 * 3600))

        XCTAssertEqual(store.addCodes([hostile]), .imported(added: 1, skipped: 0))
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

        XCTAssertEqual(result, .imported(added: 2, skipped: 2))
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

    func testTwoCodesThatOnlyShareANameAreBothSavedAndShown() async throws {
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

    // MARK: - Saving an edit screen

    func testAnEditOnlyChangesWhatTheScreenChanged() {
        let opened = OTPCode(label: "Bank", account: "user", secret: "JBSWY3DPEHPK3PXP",
                             kind: .hotp, counter: 3, modifiedAt: Date().addingTimeInterval(-60))
        store.addCode(opened)
        // While the edit screen is open: a code is spent and the code is pinned.
        store.advanceCounter(for: opened)
        store.setPinned(true, for: opened)

        let outcome = store.saveEdit(from: opened, to: opened.edited(label: "Bank (personal)",
                                                                      modifiedAt: opened.modifiedAt))

        XCTAssertEqual(outcome, .saved)
        let saved = store.codes.first { $0.id == opened.id }
        XCTAssertEqual(saved?.label, "Bank (personal)")
        XCTAssertEqual(saved?.counter, 4, "the code spent meanwhile stays spent")
        XCTAssertEqual(saved?.isPinned, true, "and the pin made meanwhile stays")
    }

    func testAnEditCanStillSetTheCounterOnPurpose() {
        let opened = OTPCode(label: "Bank", account: "user", secret: "JBSWY3DPEHPK3PXP",
                             kind: .hotp, counter: 3)
        store.addCode(opened)

        XCTAssertEqual(store.saveEdit(from: opened, to: opened.edited(counter: 9)), .saved)
        XCTAssertEqual(store.codes.first { $0.id == opened.id }?.counter, 9)
    }

    func testAnEditNeverLowersACounterThatMovedOnMeanwhile() {
        let opened = OTPCode(label: "Bank", account: "user", secret: "JBSWY3DPEHPK3PXP",
                             kind: .hotp, counter: 3)
        store.addCode(opened)
        // Codes spent while the screen was open: 3 → 12.
        for _ in 0..<9 { store.advanceCounter(for: opened) }

        // The user nudged the stepper up from the 3 the screen opened with.
        XCTAssertEqual(store.saveEdit(from: opened, to: opened.edited(counter: 5)), .saved)

        XCTAssertEqual(store.codes.first { $0.id == opened.id }?.counter, 12,
                       "a counter that goes back is a code already used")
    }

    func testAnEditToACodeDeletedMeanwhileIsReportedAndNotSaved() {
        let opened = token("GitHub")
        store.addCode(opened)
        store.removeCode(opened)

        XCTAssertEqual(store.saveEdit(from: opened, to: opened.edited(label: "GitHub Work")), .deleted)
        XCTAssertTrue(store.codes.isEmpty)
    }

    func testAnEditOntoAnotherCodesNameIsReported() {
        let opened = token("GitHub")
        store.addCode(opened)
        store.addCode(token("GitLab"))

        XCTAssertEqual(store.saveEdit(from: opened, to: opened.edited(label: "GitLab")), .nameTaken)
        XCTAssertEqual(store.codes.first { $0.id == opened.id }?.label, "GitHub")
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

    func testDeletingFromICloudWaitsForTheSyncAlreadyRunning() async throws {
        let gate = Gate()
        holdSyncs(until: gate)

        let syncing = Task { await store.syncNow() }
        await waitUntil { self.sync.events.contains("sync started") }
        let deleting = Task { try await store.disableSync(deleteCloudData: true) }
        // An edit asks for a sync of its own while the delete is waiting.
        store.addCode(token("GitHub"))
        try await Task.sleep(for: .milliseconds(800))
        XCTAssertFalse(sync.events.contains("deleted"), "the delete must wait for the running sync")

        gate.isOpen = true
        await syncing.value
        try await deleting.value

        XCTAssertEqual(sync.events, ["sync started", "sync finished", "deleted"],
                       "and no sync may start before the delete is done")
        XCTAssertFalse(store.isSyncEnabled)
    }

    /// Holds the fake's sync open until the test lets it finish.
    private final class Gate { var isOpen = false }

    private func holdSyncs(until gate: Gate) {
        sync.handler = { [sync] _ in
            sync!.events.append("sync started")
            // Bounded, so a test that never opens the gate fails instead of hanging.
            let deadline = ContinuousClock.now + .seconds(5)
            while !gate.isOpen, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(10))
            }
            sync!.events.append("sync finished")
            return nil
        }
    }

    func testASecondDeleteFromICloudWaitsForTheFirst() async throws {
        let gate = Gate()
        holdSyncs(until: gate)

        let syncing = Task { await store.syncNow() }
        await waitUntil { self.sync.events.contains("sync started") }
        let first = Task { try await store.disableSync(deleteCloudData: true) }
        await waitUntil { self.store.isDeletingCloudData }
        // Tapped again while the first is still waiting.
        var secondReturned = false
        let second = Task {
            try await store.disableSync(deleteCloudData: true)
            secondReturned = true
        }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(secondReturned, "the second call waits for the first rather than reporting success")
        XCTAssertTrue(store.isDeletingCloudData)

        gate.isOpen = true
        await syncing.value
        try await first.value
        try await second.value

        XCTAssertEqual(sync.events, ["sync started", "sync finished", "deleted"], "one delete, and no sync during it")
        XCTAssertFalse(store.isDeletingCloudData)
        XCTAssertFalse(store.isSyncEnabled)
    }

    func testASecondDeleteFromICloudSharesTheFirstOnesFailure() async {
        struct Offline: Error {}
        sync.deleteError = Offline()
        let gate = Gate()
        holdSyncs(until: gate)

        let syncing = Task { await store.syncNow() }
        await waitUntil { self.sync.events.contains("sync started") }
        let first = Task { try await store.disableSync(deleteCloudData: true) }
        await waitUntil { self.store.isDeletingCloudData }
        let second = Task { try await store.disableSync(deleteCloudData: true) }
        try? await Task.sleep(for: .milliseconds(50))

        gate.isOpen = true
        await syncing.value
        let firstFailed = await (try? first.value) == nil
        let secondFailed = await (try? second.value) == nil

        XCTAssertTrue(firstFailed)
        XCTAssertTrue(secondFailed, "the second call reports the same failure")
        XCTAssertTrue(store.isSyncEnabled, "and sync stays on")
    }

    func testAFailedDeleteFromICloudStillSyncsTheEditItCancelled() async {
        struct Offline: Error {}
        sync.deleteError = Offline()
        var uploaded: [String] = []
        sync.handler = { local in
            uploaded = local.tokens.map(\.label)
            return nil
        }

        // An edit, and then — before its sync has started — a delete that fails.
        store.addCode(token("GitHub"))
        do {
            try await store.disableSync(deleteCloudData: true)
            XCTFail("the delete was meant to fail")
        } catch {}

        XCTAssertTrue(store.isSyncEnabled, "a failed delete leaves sync on")
        await waitUntil { uploaded.contains("GitHub") }
    }

    func testRestoringABackupThatRepeatsAnIDKeepsOneAndSyncs() async {
        let first = token("GitHub")
        let repeated = OTPCode(id: first.id, label: "GitLab", account: "user", secret: "JBSWY3DPEHPK3PXP")

        store.replaceAll(with: [first, repeated])

        XCTAssertEqual(store.codes.map(\.label), ["GitHub"], "the first copy of a repeated id is kept")
        let snapshot = await runSync { _ in nil }
        XCTAssertEqual(snapshot?.tokens.count, 1)
    }

    func testRestoringAnOlderBackupNeverPutsACounterBack() async {
        let counterBased = OTPCode(label: "Bank", account: "user", secret: "JBSWY3DPEHPK3PXP",
                                   kind: .hotp, counter: 3)
        store.addCode(counterBased)
        // Backed up on 3 under another name, then codes 3 and 4 were spent here.
        let backedUp = counterBased.edited(label: "Bank (old)")
        store.advanceCounter(for: counterBased)
        store.advanceCounter(for: counterBased)

        store.replaceAll(with: [backedUp])

        let code = store.codes.first { $0.id == counterBased.id }
        XCTAssertEqual(code?.label, "Bank (old)", "the backup still wins everything else")
        XCTAssertEqual(code?.counter, 5, "but a spent code must not come back")
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

    func testAVaultThatWontDecodeIsLeftAloneAndEditsAreRefused() async {
        // Present but unreadable — corruption, or a field from a newer build. The
        // first edit used to save `[]` over it.
        let stored = Data("not a list of codes".utf8)
        XCTAssertTrue(KeychainStore.save(stored, account: "otpCodes"))

        let unreadable = OTPDataStore(syncService: FakeTokenSyncService(), watchRelay: DisabledWatchTokenRelay())

        XCTAssertFalse(unreadable.isVaultLoaded)
        XCTAssertTrue(unreadable.hasUnreadableCodes)
        XCTAssertFalse(unreadable.addCode(token("GitHub")), "an edit must not look saved when it can't be")
        XCTAssertEqual(unreadable.addCodes([token("GitLab")]), .vaultUnavailable,
                       "a refused import must not read as \"all duplicates\"")
        XCTAssertFalse(unreadable.replaceAll(with: [token("GitLab")]),
                       "a refused restore must not read as restored")
        XCTAssertTrue(unreadable.codes.isEmpty)
        XCTAssertEqual(KeychainStore.load(account: "otpCodes"), stored)
    }

    func testUnreadableCodesCanBeSetAsideToStartOver() async throws {
        let setAsideAccount = OTPDataStore.setAsideAccount
        let previouslySetAside = KeychainStore.load(account: setAsideAccount)
        defer {
            if let previouslySetAside {
                _ = KeychainStore.save(previouslySetAside, account: setAsideAccount)
            } else {
                deleteKeychainItem(account: setAsideAccount)
            }
        }
        let stored = Data("not a list of codes".utf8)
        XCTAssertTrue(KeychainStore.save(stored, account: "otpCodes"))
        let relay = RecordingWatchTokenRelay()
        let unreadable = OTPDataStore(syncService: FakeTokenSyncService(), watchRelay: relay)

        XCTAssertTrue(unreadable.setAsideUnreadableCodes())

        XCTAssertEqual(KeychainStore.load(account: setAsideAccount), stored,
                       "the unreadable codes are kept, not thrown away")
        XCTAssertTrue(unreadable.isVaultLoaded)
        XCTAssertFalse(unreadable.hasUnreadableCodes)
        XCTAssertTrue(relay.pushes.isEmpty,
                      "the watch's copy may be the only readable one; starting over must not clear it")
        XCTAssertTrue(unreadable.addCode(token("GitHub")), "the vault works again")
        XCTAssertEqual(relay.pushes.last?.map(\.label), ["GitHub"], "and the next real change updates the watch")
        let saved = try JSONDecoder().decode([OTPCode].self,
                                             from: try XCTUnwrap(KeychainStore.load(account: "otpCodes")))
        XCTAssertEqual(saved.map(\.label), ["GitHub"])

        // Setting aside again replaces the one copy rather than adding another.
        let newer = Data("different unreadable bytes".utf8)
        XCTAssertTrue(KeychainStore.save(newer, account: "otpCodes"))
        let again = OTPDataStore(syncService: FakeTokenSyncService(), watchRelay: DisabledWatchTokenRelay())
        XCTAssertTrue(again.setAsideUnreadableCodes())
        XCTAssertEqual(KeychainStore.load(account: setAsideAccount), newer)
    }

    func testALockedVaultIsNeverSetAside() async {
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

    func testAnUnreadableTrashDoesNotHoldUpTheCodesAndIsNotWrittenOver() async throws {
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

    /// What happened, in order, for tests of how syncing and deleting interleave.
    var events: [String] = []

    /// Thrown by `deleteRemoteRecords` when set, as a network failure would be.
    var deleteError: Error?

    func deleteRemoteRecords() async throws {
        if let deleteError { throw deleteError }
        events.append("deleted")
    }
    func handleRemoteNotification(userInfo: [AnyHashable: Any]) -> Bool { false }
}

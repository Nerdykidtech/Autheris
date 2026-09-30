import XCTest
@testable import Vaultic

/// The conflict-resolution rules, asserted directly.
///
/// `SyncMergeEngine` is pure by construction — no I/O and no clock reads — so
/// every case below pins `now` and the retention window rather than reading the
/// real clock. That is what makes these assertions deterministic.
final class SyncMergeEngineTests: XCTestCase {

    /// Fixed "current time" for every case in this file.
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let retention = SyncMergeEngine.defaultTombstoneRetention

    // MARK: - Helpers

    private func token(
        id: UUID = UUID(),
        label: String = "GitHub",
        account: String = "octocat",
        secret: String = "JBSWY3DPEHPK3PXP",
        algorithm: OTPAlgorithm = .sha1,
        digits: Int = 6,
        period: Int = 30,
        kind: OTPKind = .totp,
        counter: UInt64 = 0,
        timerRingHex: String? = nil,
        isPinned: Bool = false,
        modifiedAt: Date
    ) -> OTPCode {
        OTPCode(id: id, label: label, account: account, secret: secret,
                algorithm: algorithm, digits: digits, period: period,
                kind: kind, counter: counter,
                timerRingHex: timerRingHex, isPinned: isPinned, modifiedAt: modifiedAt)
    }

    private func merge(local: SyncLocalState, remote: [SyncRecord]) -> SyncMergeOutcome {
        SyncMergeEngine.merge(local: local, remote: remote,
                              now: now, tombstoneRetention: retention)
    }

    private func tombstone(_ id: UUID, deletedAt: Date) -> SyncRecord {
        .tombstone(id: id.uuidString, deletedAt: deletedAt)
    }

    // MARK: - 1. Local token, empty cloud

    func testLocalTokenWithEmptyCloudIsUploadedAndNothingIsAdopted() {
        let local = token(modifiedAt: now)

        let outcome = merge(local: SyncLocalState(tokens: [local]), remote: [])

        XCTAssertEqual(outcome.uploads.map(\.id), [local.id.uuidString])
        XCTAssertFalse(outcome.didAdoptRemoteChanges)
        XCTAssertEqual(outcome.tokens.map(\.id), [local.id])
    }

    // MARK: - 2. Remote-only token

    func testRemoteOnlyTokenIsAdoptedAndNotEchoedBack() {
        let remote = token(modifiedAt: now)

        let outcome = merge(local: SyncLocalState(), remote: [.live(remote)])

        XCTAssertEqual(outcome.tokens.map(\.id), [remote.id])
        XCTAssertTrue(outcome.didAdoptRemoteChanges)
        // Adopting must not mark the record for upload, or two devices would
        // ping-pong the same record forever.
        XCTAssertTrue(outcome.uploads.isEmpty)
    }

    func testRemoteOnlyTokenIsAppendedWithoutReshufflingLocalOrder() {
        let first = token(label: "First", modifiedAt: now)
        let second = token(label: "Second", modifiedAt: now)
        let incoming = token(label: "Incoming", modifiedAt: now)

        let outcome = merge(local: SyncLocalState(tokens: [first, second]),
                            remote: [.live(incoming)])

        XCTAssertEqual(outcome.tokens.map(\.label), ["First", "Second", "Incoming"])
    }

    // MARK: - 3. Remote edit newer

    func testNewerRemoteEditIsAdoptedAndNothingIsUploaded() {
        let id = UUID()
        let local = token(id: id, label: "Older", modifiedAt: now)
        let remote = token(id: id, label: "Newer", modifiedAt: now.addingTimeInterval(60))

        let outcome = merge(local: SyncLocalState(tokens: [local]), remote: [.live(remote)])

        XCTAssertEqual(outcome.tokens.map(\.label), ["Newer"])
        XCTAssertTrue(outcome.uploads.isEmpty)
        XCTAssertTrue(outcome.didAdoptRemoteChanges)
    }

    // MARK: - 4. Local edit newer

    func testNewerLocalEditIsUploadedAndRemoteIsNotAdopted() {
        let id = UUID()
        let local = token(id: id, label: "Newer", modifiedAt: now.addingTimeInterval(60))
        let remote = token(id: id, label: "Older", modifiedAt: now)

        let outcome = merge(local: SyncLocalState(tokens: [local]), remote: [.live(remote)])

        XCTAssertEqual(outcome.tokens.map(\.label), ["Newer"])
        XCTAssertEqual(outcome.uploads.map(\.id), [id.uuidString])
        XCTAssertFalse(outcome.didAdoptRemoteChanges)
    }

    // MARK: - 5. Identical content

    func testIdenticalContentProducesNoWorkInEitherDirection() {
        let both = token(modifiedAt: now)

        let outcome = merge(local: SyncLocalState(tokens: [both]), remote: [.live(both)])

        XCTAssertTrue(outcome.uploads.isEmpty)
        XCTAssertFalse(outcome.didAdoptRemoteChanges)
        XCTAssertEqual(outcome.tokens.map(\.id), [both.id])
    }

    // MARK: - 6. Remote tombstone, local token

    func testNewerRemoteTombstoneRemovesTheLocalTokenAndIsRemembered() {
        let id = UUID()
        let local = token(id: id, modifiedAt: now)
        let deletedAt = now.addingTimeInterval(60)

        let outcome = merge(local: SyncLocalState(tokens: [local]),
                            remote: [tombstone(id, deletedAt: deletedAt)])

        XCTAssertTrue(outcome.tokens.isEmpty)
        XCTAssertEqual(outcome.tombstones[id.uuidString], deletedAt)
        XCTAssertTrue(outcome.didAdoptRemoteChanges)
        XCTAssertTrue(outcome.uploads.isEmpty)
    }

    // MARK: - 7. Local tombstone newer than a remote edit

    func testNewerLocalTombstoneIsUploadedAndTheTokenIsNotResurrected() {
        let id = UUID()
        let deletedAt = now.addingTimeInterval(60)

        let outcome = merge(local: SyncLocalState(tombstones: [id.uuidString: deletedAt]),
                            remote: [.live(token(id: id, modifiedAt: now))])

        XCTAssertTrue(outcome.tokens.isEmpty)
        XCTAssertEqual(outcome.uploads.map(\.id), [id.uuidString])
        XCTAssertTrue(outcome.uploads.allSatisfy(\.deleted))
        XCTAssertFalse(outcome.didAdoptRemoteChanges)
    }

    // MARK: - 8. Local edit newer than a remote tombstone

    func testNewerLocalEditSurvivesARemoteTombstoneAndIsReuploaded() {
        let id = UUID()
        let local = token(id: id, modifiedAt: now.addingTimeInterval(60))

        let outcome = merge(local: SyncLocalState(tokens: [local]),
                            remote: [tombstone(id, deletedAt: now)])

        XCTAssertEqual(outcome.tokens.map(\.id), [id])
        XCTAssertEqual(outcome.uploads.map(\.id), [id.uuidString])
        XCTAssertFalse(outcome.uploads.contains(where: \.deleted))
        XCTAssertFalse(outcome.didAdoptRemoteChanges)
    }

    // MARK: - 9. Equal timestamps, different content

    func testEqualTimestampsWithDifferentContentConvergeOnOneValue() {
        let id = UUID()
        let alpha = token(id: id, label: "Alpha", modifiedAt: now)
        let beta = token(id: id, label: "Beta", modifiedAt: now)

        // Device A holds `alpha` and sees `beta` in iCloud; device B is the mirror
        // image. The tie-break has to pick the same winner on both, or the two
        // devices would swap values on every sync.
        let deviceA = merge(local: SyncLocalState(tokens: [alpha]), remote: [.live(beta)])
        let deviceB = merge(local: SyncLocalState(tokens: [beta]), remote: [.live(alpha)])

        XCTAssertEqual(deviceA.tokens.map(\.label), deviceB.tokens.map(\.label))
        // Exactly one side uploads, so they actually settle instead of both
        // pushing their own copy.
        XCTAssertEqual(deviceA.uploads.count + deviceB.uploads.count, 1)
    }

    // MARK: - 10. Token persisted before sync existed

    func testTokenDatedDistantPastLosesToADatedRemoteEdit() {
        let id = UUID()
        let legacy = token(id: id, label: "Legacy", modifiedAt: .distantPast)
        let remote = token(id: id, label: "Edited", modifiedAt: now)

        let outcome = merge(local: SyncLocalState(tokens: [legacy]), remote: [.live(remote)])

        XCTAssertEqual(outcome.tokens.map(\.label), ["Edited"])
        XCTAssertTrue(outcome.uploads.isEmpty)
    }

    // MARK: - 11. Tombstone older than the retention window

    func testStaleLocalTombstoneIsDroppedAndNotUploaded() {
        let id = UUID()
        let stale = now.addingTimeInterval(-(retention + 60))

        let outcome = merge(local: SyncLocalState(tombstones: [id.uuidString: stale]), remote: [])

        XCTAssertTrue(outcome.uploads.isEmpty)
        XCTAssertTrue(outcome.tombstones.isEmpty)
    }

    func testStaleRemoteTombstoneIsIgnored() {
        let id = UUID()
        let stale = now.addingTimeInterval(-(retention + 60))

        let outcome = merge(local: SyncLocalState(), remote: [tombstone(id, deletedAt: stale)])

        XCTAssertTrue(outcome.tokens.isEmpty)
        XCTAssertTrue(outcome.tombstones.isEmpty)
        XCTAssertFalse(outcome.didAdoptRemoteChanges)
    }

    func testTombstoneInsideTheRetentionWindowIsStillReplicated() {
        let id = UUID()
        let recent = now.addingTimeInterval(-(retention - 60))

        let outcome = merge(local: SyncLocalState(tombstones: [id.uuidString: recent]), remote: [])

        XCTAssertEqual(outcome.uploads.map(\.id), [id.uuidString])
        XCTAssertEqual(outcome.tombstones[id.uuidString], recent)
    }

    // MARK: - 12. Round-trip of the previous outcome

    func testMergingTheOutcomeAgainIsAFixedPoint() {
        let local = token(modifiedAt: now)

        let first = merge(local: SyncLocalState(tokens: [local]), remote: [])
        XCTAssertEqual(first.uploads.count, 1, "precondition: the token needs uploading")

        // Feed the result back in with the uploads now present in iCloud.
        let second = merge(local: SyncLocalState(tokens: first.tokens,
                                                 tombstones: first.tombstones),
                           remote: first.uploads)

        XCTAssertTrue(second.uploads.isEmpty)
        XCTAssertFalse(second.didAdoptRemoteChanges)
        XCTAssertEqual(second.tokens.map(\.id), first.tokens.map(\.id))
    }

    func testTombstoneRoundTripIsAlsoAFixedPoint() {
        let id = UUID()
        let local = token(id: id, modifiedAt: now)
        let first = merge(local: SyncLocalState(tokens: [local]), remote: [])
        let deletion = merge(local: SyncLocalState(tokens: first.tokens,
                                                   tombstones: first.tombstones),
                             remote: [tombstone(id, deletedAt: now.addingTimeInterval(60))])

        XCTAssertTrue(deletion.tokens.isEmpty)
        XCTAssertTrue(deletion.uploads.isEmpty, "adopting a tombstone must not bounce it back")

        let second = merge(local: SyncLocalState(tokens: deletion.tokens,
                                                 tombstones: deletion.tombstones),
                           remote: [tombstone(id, deletedAt: now.addingTimeInterval(60))])

        XCTAssertTrue(second.uploads.isEmpty)
        XCTAssertTrue(second.tokens.isEmpty)
    }

    // MARK: - Ordering and identity invariants

    func testLiveTokenSurvivesALingeringLocalTombstoneForTheSameID() {
        // If a token is re-added, a stale tombstone for the same id must not
        // delete it again. `recordsByID` gives a live token precedence.
        let id = UUID()
        let local = token(id: id, modifiedAt: now)

        let outcome = merge(local: SyncLocalState(tokens: [local],
                                                  tombstones: [id.uuidString: now.addingTimeInterval(-5)]),
                            remote: [])

        XCTAssertEqual(outcome.tokens.map(\.id), [id])
        XCTAssertEqual(outcome.uploads.map(\.id), [id.uuidString])
        XCTAssertFalse(outcome.uploads.contains(where: \.deleted))
    }

    func testLocalWinsPrefersTheNewerRecord() {
        let id = UUID()
        let newer = token(id: id, label: "Newer", modifiedAt: now.addingTimeInterval(60))
        let older = token(id: id, label: "Older", modifiedAt: now)

        XCTAssertTrue(SyncMergeEngine.localWins(.live(newer), over: .live(older)))
        XCTAssertFalse(SyncMergeEngine.localWins(.live(older), over: .live(newer)))
    }

    // MARK: - Fingerprints

    func testFingerprintIsStableForIdenticalContent() {
        let id = UUID()
        let a = token(id: id, label: "Same", modifiedAt: now)
        let b = token(id: id, label: "Same", modifiedAt: now.addingTimeInterval(999))

        // `modifiedAt` is deliberately not part of the fingerprint: a pure
        // timestamp bump is not a content change and must not look like one.
        XCTAssertEqual(SyncFingerprint.forToken(a), SyncFingerprint.forToken(b))
    }

    func testFingerprintSeparatesIdenticalTokensWithDifferentIDs() {
        let one = token(label: "Same", account: "same", modifiedAt: now)
        let two = token(label: "Same", account: "same", modifiedAt: now)

        XCTAssertNotEqual(one.id, two.id, "precondition: the helper generates fresh ids")
        XCTAssertNotEqual(SyncFingerprint.forToken(one), SyncFingerprint.forToken(two))
    }

    func testFingerprintChangesWithEveryContentField() {
        let id = UUID()
        let base = token(id: id, modifiedAt: now)
        let baseFingerprint = SyncFingerprint.forToken(base)

        XCTAssertNotEqual(baseFingerprint, SyncFingerprint.forToken(token(id: id, label: "Other", modifiedAt: now)))
        XCTAssertNotEqual(baseFingerprint, SyncFingerprint.forToken(token(id: id, account: "other", modifiedAt: now)))
        XCTAssertNotEqual(baseFingerprint, SyncFingerprint.forToken(token(id: id, secret: "KRSXG5CTMVRXEZLU", modifiedAt: now)))
        XCTAssertNotEqual(baseFingerprint, SyncFingerprint.forToken(token(id: id, algorithm: .sha256, modifiedAt: now)))
        XCTAssertNotEqual(baseFingerprint, SyncFingerprint.forToken(token(id: id, digits: 8, modifiedAt: now)))
        XCTAssertNotEqual(baseFingerprint, SyncFingerprint.forToken(token(id: id, period: 60, modifiedAt: now)))
        XCTAssertNotEqual(baseFingerprint, SyncFingerprint.forToken(token(id: id, timerRingHex: "FF8800", modifiedAt: now)))
        // Pinning has to be visible to the fingerprint, or toggling a pin would
        // look like "no change" and never reach the user's other devices.
        XCTAssertNotEqual(baseFingerprint, SyncFingerprint.forToken(token(id: id, isPinned: true, modifiedAt: now)))
        // And so do the two halves of a counter-based code. The counter is the one
        // that matters most: a fingerprint that ignored it would make spending a
        // code look like "no change", so the device the user is *not* holding would
        // keep offering the code they just used.
        XCTAssertNotEqual(baseFingerprint, SyncFingerprint.forToken(token(id: id, kind: .hotp, modifiedAt: now)))
        XCTAssertNotEqual(baseFingerprint, SyncFingerprint.forToken(token(id: id, counter: 4, modifiedAt: now)))
    }

    func testTombstoneFingerprintIsTheConstantSentinel() {
        let id = UUID()
        let record = tombstone(id, deletedAt: now)

        XCTAssertEqual(record.fingerprint, SyncFingerprint.tombstone)
        XCTAssertNil(record.token)
        XCTAssertTrue(record.deleted)
    }
}

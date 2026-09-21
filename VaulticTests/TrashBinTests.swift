import XCTest
@testable import Vaultic

/// `TrashBin` decides how long a deleted token stays recoverable and what
/// restoring it does to the rest of the vault. The cases that matter most are the
/// retention boundary and the interaction with the tombstone the delete left.
final class TrashBinTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let retention = TrashBin.defaultRetention

    private func token(
        id: UUID = UUID(),
        label: String = "GitHub",
        account: String = "octocat",
        secret: String = "JBSWY3DPEHPK3PXP",
        modifiedAt: Date = Date(timeIntervalSince1970: 1_600_000_000)
    ) -> OTPCode {
        OTPCode(id: id, label: label, account: account, secret: secret, modifiedAt: modifiedAt)
    }

    private func entry(
        _ code: OTPCode,
        deletedAt: Date,
        id: UUID = UUID()
    ) -> TrashBin.Entry {
        TrashBin.Entry(id: id, code: code, deletedAt: deletedAt)
    }

    // MARK: - The advertised window

    func testTheAdvertisedWindowIsSevenDays() {
        // The Settings copy and the empty state both read this, so pin it.
        XCTAssertEqual(TrashBin.retentionDays, 7)
        XCTAssertEqual(TrashBin.defaultRetention, 7 * 24 * 60 * 60)
    }

    // MARK: - Retention sweep

    func testAnEntryExactlyOnTheBoundaryIsStillKept() {
        // Matches `SyncMergeEngine`'s tombstone convention: older than the window
        // expires, exactly the window does not.
        let onTheBoundary = entry(token(), deletedAt: now.addingTimeInterval(-retention))

        let sweep = TrashBin.sweep([onTheBoundary], now: now, retention: retention)

        XCTAssertEqual(sweep.kept.map(\.id), [onTheBoundary.id])
        XCTAssertTrue(sweep.expired.isEmpty)
        XCTAssertFalse(sweep.didExpireAnything)
    }

    func testAnEntryJustPastTheBoundaryExpires() {
        let justPast = entry(token(), deletedAt: now.addingTimeInterval(-(retention + 1)))

        let sweep = TrashBin.sweep([justPast], now: now, retention: retention)

        XCTAssertTrue(sweep.kept.isEmpty)
        XCTAssertEqual(sweep.expired.map(\.id), [justPast.id])
        XCTAssertTrue(sweep.didExpireAnything)
    }

    func testAFreshEntryIsKept() {
        let fresh = entry(token(), deletedAt: now.addingTimeInterval(-60))

        let sweep = TrashBin.sweep([fresh], now: now, retention: retention)

        XCTAssertEqual(sweep.kept.map(\.id), [fresh.id])
        XCTAssertTrue(sweep.expired.isEmpty)
    }

    func testSweepSeparatesMixedAgesAndPreservesTheKeptOnes() {
        let fresh = entry(token(label: "Fresh"), deletedAt: now.addingTimeInterval(-60))
        let stale = entry(token(label: "Stale"), deletedAt: now.addingTimeInterval(-(retention + 60)))
        let middling = entry(token(label: "Mid"), deletedAt: now.addingTimeInterval(-(retention / 2)))

        let sweep = TrashBin.sweep([fresh, stale, middling], now: now, retention: retention)

        XCTAssertEqual(sweep.kept.map(\.code.label), ["Fresh", "Mid"])
        XCTAssertEqual(sweep.expired.map(\.code.label), ["Stale"])
    }

    func testSweepingNothingExpiresNothing() {
        let sweep = TrashBin.sweep([], now: now, retention: retention)

        XCTAssertTrue(sweep.kept.isEmpty)
        XCTAssertFalse(sweep.didExpireAnything)
    }

    // MARK: - Restore

    func testRestoreReturnsTheSameTokenContentWithAFreshTimestamp() {
        let original = token(modifiedAt: Date(timeIntervalSince1970: 1_000_000))
        let restoreNow = Date(timeIntervalSince1970: 1_500_000)

        guard case .restored(let restored) = TrashBin.restore(entry(original, deletedAt: now), into: [], at: restoreNow) else {
            return XCTFail("expected the restore to succeed")
        }

        XCTAssertEqual(restored.id, original.id)
        XCTAssertEqual(restored.label, original.label)
        XCTAssertEqual(restored.account, original.account)
        XCTAssertEqual(restored.secret, original.secret)
        // Stamped with `now`, not the original timestamp — that is what makes the
        // restore a newer write than the delete it is undoing.
        XCTAssertEqual(restored.modifiedAt, restoreNow)
        XCTAssertGreaterThan(restored.modifiedAt, original.modifiedAt)
    }

    func testRestoreIsRefusedWhenTheIDIsAlreadyInUse() {
        let original = token()
        let occupant = token(id: original.id, label: "Something Else")

        let outcome = TrashBin.restore(entry(original, deletedAt: now), into: [occupant], at: now)

        XCTAssertEqual(outcome, .collides)
    }

    func testRestoreIsRefusedWhenTheLabelAndAccountAreAlreadyInUse() {
        // Matches `OTPDataStore.addCode`: the same label+account counts as "the
        // same token" even under a different id.
        let original = token(label: "GitHub", account: "octocat")
        let occupant = token(label: "GitHub", account: "octocat")

        let outcome = TrashBin.restore(entry(original, deletedAt: now), into: [occupant], at: now)

        XCTAssertEqual(outcome, .collides)
    }

    func testRestoreSucceedsWhenOnlyTheAccountDiffers() {
        let original = token(label: "GitHub", account: "octocat")
        let other = token(label: "GitHub", account: "someone-else")

        guard case .restored = TrashBin.restore(entry(original, deletedAt: now), into: [other], at: now) else {
            return XCTFail("a different account is a different token")
        }
    }

    func testRestoreSucceedsIntoAnEmptyVault() {
        guard case .restored = TrashBin.restore(entry(token(), deletedAt: now), into: [], at: now) else {
            return XCTFail("nothing to collide with")
        }
    }

    /// The property that makes restore actually work, checked against the real
    /// merge engine rather than by inspection.
    func testRestoredTokenSurvivesTheTombstoneTheDeleteLeftBehind() {
        let id = UUID()
        let original = token(id: id, modifiedAt: Date(timeIntervalSince1970: 1_000_000))
        let deletedAt = Date(timeIntervalSince1970: 1_010_000)
        let restoreNow = Date(timeIntervalSince1970: 1_020_000)

        guard case .restored(let restored) = TrashBin.restore(entry(original, deletedAt: deletedAt), into: [], at: restoreNow) else {
            return XCTFail("expected the restore to succeed")
        }

        let outcome = SyncMergeEngine.merge(
            local: SyncLocalState(tokens: [restored],
                                  tombstones: [id.uuidString: deletedAt]),
            remote: [.tombstone(id: id.uuidString, deletedAt: deletedAt)],
            now: restoreNow.addingTimeInterval(60),
            tombstoneRetention: SyncMergeEngine.defaultTombstoneRetention
        )

        XCTAssertEqual(outcome.tokens.map(\.id), [id],
                       "the restored token has to outrank the tombstone, or sync deletes it again")
        XCTAssertEqual(outcome.uploads.map(\.id), [id.uuidString])
        XCTAssertFalse(outcome.uploads.contains(where: \.deleted),
                       "re-uploading the token must not re-send the deletion")
    }

    // MARK: - Collision helper

    func testCollidesOnMatchingIDEvenWithDifferentContent() {
        let existing = token(label: "A", account: "a")

        XCTAssertTrue(TrashBin.collides(token(id: existing.id, label: "B", account: "b"),
                                        with: [existing]))
    }

    func testCollidesOnMatchingLabelAndAccountUnderADifferentID() {
        let existing = token(label: "GitHub", account: "octocat")

        XCTAssertTrue(TrashBin.collides(token(label: "GitHub", account: "octocat"),
                                        with: [existing]))
    }

    func testDoesNotCollideAgainstAnEmptyVault() {
        XCTAssertFalse(TrashBin.collides(token(), with: []))
    }

    func testWithNoAccountTheLabelAloneDecidesIdentity() {
        // The consequence of letting Account be left blank: a token with no account
        // is identified by its label alone, so two different services that happen to
        // share a name are treated as one token — which is also what lets a single
        // delete remove them together. Worth knowing when the account is omitted, so
        // it is pinned rather than discovered.
        let existing = token(label: "GitHub", account: "")
        let sameName = token(label: "GitHub", account: "")

        XCTAssertTrue(TrashBin.collides(sameName, with: [existing]))
        XCTAssertFalse(TrashBin.collides(token(label: "GitLab", account: ""), with: [existing]))
    }

    // MARK: - Ordering and persistence

    func testNewestFirstOrdersByDeletionTime() {
        let oldest = entry(token(label: "Oldest"), deletedAt: now.addingTimeInterval(-300))
        let newest = entry(token(label: "Newest"), deletedAt: now.addingTimeInterval(-10))
        let middle = entry(token(label: "Middle"), deletedAt: now.addingTimeInterval(-100))

        XCTAssertEqual(TrashBin.newestFirst([oldest, newest, middle]).map(\.code.label),
                       ["Newest", "Middle", "Oldest"])
    }

    func testEncodeDecodeRoundTripPreservesEntries() throws {
        let entries = [entry(token(label: "One"), deletedAt: now),
                       entry(token(label: "Two"), deletedAt: now.addingTimeInterval(-60))]

        let decoded = TrashBin.decode(try XCTUnwrap(TrashBin.encode(entries)))

        XCTAssertEqual(decoded, entries)
    }

    func testDecodeToleratesMissingOrCorruptData() {
        XCTAssertTrue(TrashBin.decode(nil).isEmpty)
        XCTAssertTrue(TrashBin.decode(Data()).isEmpty)
        XCTAssertTrue(TrashBin.decode(Data("not json".utf8)).isEmpty)
        XCTAssertTrue(TrashBin.decode(Data("{\"unexpected\":1}".utf8)).isEmpty)
    }

    func testAnEntryIDIsIndependentOfTheTokenID() {
        // Delete → restore → delete again has to produce two distinct rows, or
        // SwiftUI's List diffing sees one identity twice.
        let code = token()
        let first = entry(code, deletedAt: now)
        let second = entry(code, deletedAt: now.addingTimeInterval(60))

        XCTAssertEqual(first.code.id, second.code.id)
        XCTAssertNotEqual(first.id, second.id)
    }

    func testExpiryIsTheDeletionTimePlusTheWindow() {
        let deletedAt = now.addingTimeInterval(-1_000)
        let subject = entry(token(), deletedAt: deletedAt)

        XCTAssertEqual(subject.expiry(), deletedAt.addingTimeInterval(retention))
        XCTAssertEqual(subject.expiry(retention: 60), deletedAt.addingTimeInterval(60))
    }
}

import XCTest
@testable import Vaultic

/// The precedence rules here decide whether a deleted token stays deleted, so
/// the cases that matter most are the ones where two copies disagree.
final class SyncTombstoneStoreTests: XCTestCase {

    private let knownID = "3F2504E0-4F89-11D3-9A0C-0305E82C3301"

    /// 1_700_000_000 as `Date`'s reference-date offset, i.e. what
    /// `JSONEncoder` with its default `.deferredToDate` strategy writes.
    private let referenceDateOffset = 721_692_800.0

    private func blob(_ tombstones: [String: Date]) throws -> Data {
        try XCTUnwrap(SyncTombstoneStore.encode(tombstones))
    }

    // MARK: - Round trip

    func testEncodeDecodeRoundTripPreservesEveryTombstone() throws {
        let original = [knownID: Date(timeIntervalSince1970: 1_700_000_000),
                        "another-id": Date(timeIntervalSince1970: 1_600_000_000)]

        let decoded = SyncTombstoneStore.decode(try blob(original))

        XCTAssertEqual(decoded.count, 2)
        for (id, date) in original {
            XCTAssertEqual(try XCTUnwrap(decoded[id]).timeIntervalSince1970,
                           date.timeIntervalSince1970, accuracy: 0.001)
        }
    }

    func testAnAbsentBlobDecodesToNoTombstones() {
        XCTAssertTrue(SyncTombstoneStore.decode(nil).isEmpty)
    }

    func testCorruptDataDecodesToNoTombstonesRatherThanThrowing() {
        XCTAssertTrue(SyncTombstoneStore.decode(Data("not json".utf8)).isEmpty)
        XCTAssertTrue(SyncTombstoneStore.decode(Data()).isEmpty)
        // Valid JSON of the wrong shape is equally survivable.
        XCTAssertTrue(SyncTombstoneStore.decode(Data("[1,2,3]".utf8)).isEmpty)
    }

    /// Pins the on-disk shape so that changing the encoder's date strategy
    /// cannot silently break the migration of an existing `UserDefaults` blob.
    func testDecodesTheBlobShapeWrittenByThePreKeychainBuild() throws {
        let legacy = Data("{\"\(knownID)\":\(referenceDateOffset)}".utf8)

        let decoded = SyncTombstoneStore.decode(legacy)

        let date = try XCTUnwrap(decoded[knownID])
        XCTAssertEqual(date.timeIntervalSince1970, 1_700_000_000, accuracy: 0.001)
    }

    // MARK: - Precedence

    func testKeychainWinsWhenBothCopiesExist() throws {
        let keychain = try blob([knownID: Date(timeIntervalSince1970: 1_700_000_000)])
        let legacy = try blob(["stale-id": Date(timeIntervalSince1970: 1_500_000_000)])

        let resolution = SyncTombstoneStore.resolve(keychain: keychain, legacyDefaults: legacy)

        XCTAssertEqual(resolution.tombstones.keys.sorted(), [knownID])
        XCTAssertTrue(resolution.removeLegacyCopy)
    }

    func testPresentButEmptyKeychainStillBeatsTheLegacyCopy() throws {
        // The regression this guards: treating an empty Keychain value as "no
        // value" and falling back to `UserDefaults` would bring back deletions
        // that had already finished propagating.
        let emptyKeychain = try blob([:])
        let legacy = try blob([knownID: Date(timeIntervalSince1970: 1_700_000_000)])

        let resolution = SyncTombstoneStore.resolve(keychain: emptyKeychain, legacyDefaults: legacy)

        XCTAssertTrue(resolution.tombstones.isEmpty)
        XCTAssertTrue(resolution.removeLegacyCopy)
    }

    func testLegacyCopyIsAdoptedOnceWhenTheKeychainIsEmpty() throws {
        let legacy = try blob([knownID: Date(timeIntervalSince1970: 1_700_000_000)])

        let resolution = SyncTombstoneStore.resolve(keychain: nil, legacyDefaults: legacy)

        XCTAssertEqual(resolution.tombstones.keys.sorted(), [knownID])
        XCTAssertTrue(resolution.removeLegacyCopy)
    }

    func testNothingToReadOnAFreshInstall() {
        let resolution = SyncTombstoneStore.resolve(keychain: nil, legacyDefaults: nil)

        XCTAssertTrue(resolution.tombstones.isEmpty)
        XCTAssertFalse(resolution.removeLegacyCopy)
    }

    func testAKeychainCopyNeedsNoLegacyCleanupWhenThereIsNone() throws {
        let keychain = try blob([knownID: Date(timeIntervalSince1970: 1_700_000_000)])

        let resolution = SyncTombstoneStore.resolve(keychain: keychain, legacyDefaults: nil)

        XCTAssertEqual(resolution.tombstones.keys.sorted(), [knownID])
        XCTAssertFalse(resolution.removeLegacyCopy)
    }

    func testCorruptKeychainDataDoesNotFallBackToTheLegacyCopy() throws {
        // If the Keychain item exists but cannot be read, the device knows it has
        // *some* bookkeeping and must not silently adopt a different set. Losing
        // tombstones is recoverable; inventing them from stale data is not.
        let legacy = try blob([knownID: Date(timeIntervalSince1970: 1_700_000_000)])

        let resolution = SyncTombstoneStore.resolve(keychain: Data("corrupt".utf8),
                                                    legacyDefaults: legacy)

        XCTAssertTrue(resolution.tombstones.isEmpty)
    }
}

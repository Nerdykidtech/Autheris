import CryptoKit
import Foundation

/// One side of a sync comparison, deliberately decoupled from CloudKit so the
/// merge rules can be unit tested without a network or an iCloud account.
nonisolated struct SyncRecord {
    /// CloudKit record name. Equal to the token's `UUID.uuidString`.
    let id: String
    /// Last write. Drives the conflict rule.
    let modifiedAt: Date
    let deleted: Bool
    /// Hash of the record's content; equal fingerprints mean "no difference".
    let fingerprint: String
    /// `nil` for tombstones.
    let token: OTPCode?

    static func live(_ token: OTPCode) -> SyncRecord {
        SyncRecord(id: token.id.uuidString,
                   modifiedAt: token.modifiedAt,
                   deleted: false,
                   fingerprint: SyncFingerprint.forToken(token),
                   token: token)
    }

    static func tombstone(id: String, deletedAt: Date) -> SyncRecord {
        SyncRecord(id: id,
                   modifiedAt: deletedAt,
                   deleted: true,
                   fingerprint: SyncFingerprint.tombstone,
                   token: nil)
    }
}

/// The local half of a merge: what the device stores right now, including the
/// deletion tombstones it is still carrying.
nonisolated struct SyncLocalState {
    var tokens: [OTPCode]
    var tombstones: [String: Date]

    init(tokens: [OTPCode] = [], tombstones: [String: Date] = [:]) {
        self.tokens = tokens
        self.tombstones = tombstones
    }
}

/// What the caller should do after a merge.
nonisolated struct SyncMergeOutcome {
    /// The token list this device should now display.
    var tokens: [OTPCode]
    /// Tombstones this device should keep carrying.
    var tombstones: [String: Date]
    /// Records where local is the winner and must be pushed to CloudKit.
    var uploads: [SyncRecord]
    /// `true` when remote data changed the local token list.
    var didAdoptRemoteChanges: Bool
}

/// Content hashing for sync bookkeeping.
///
/// **Security note:** fingerprints are hashes of record content, including the
/// TOTP secret. They are stored as *plain* CloudKit fields (they must be
/// comparable without decrypting), but a SHA-256 over a high-entropy base32
/// secret is not reversible, and the token id is mixed in so the same secret on
/// two records never produces the same value.
nonisolated enum SyncFingerprint {
    /// Constant fingerprint used by tombstones: they carry no content.
    static let tombstone = "deleted"

    /// Version prefix so the canonical form can change without silently making
    /// old and new fingerprints incomparable.
    ///
    /// Bumped to `v2` when `isPinned` joined the field list, and to `v3` when
    /// `kind` and `counter` did. Every token's fingerprint therefore differs from
    /// the value its iCloud record still carries, so the first sync after upgrading
    /// re-exchanges each record once and settles. That is expected and one-time; it
    /// is the price of a fingerprint that can see every field the user can change —
    /// and for the counter it is not just bookkeeping: a fingerprint that ignored it
    /// would make spending a code look like "no change", so the device the user was
    /// *not* holding would keep generating the spent one.
    private static let version = "v3"

    static func forToken(_ token: OTPCode) -> String {
        let fields = [
            token.id.uuidString.lowercased(),
            token.label,
            token.account,
            token.secret,
            token.algorithm.rawValue,
            String(token.digits),
            String(token.period),
            token.kind.rawValue,
            String(token.counter),
            token.timerRingHex ?? "",
            token.isPinned ? "1" : "0"
        ]
        // Length-prefix every field so concatenation stays unambiguous even when
        // values contain the separator.
        var canonical = version
        for field in fields {
            canonical += "\(field.utf8.count):\(field)"
        }
        return sha256Hex(canonical)
    }

    private static func sha256Hex(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

/// Deterministic last-write-wins merge between the device's tokens and the
/// records stored in iCloud.
///
/// Rules, applied per record id:
/// - Identical fingerprints are already converged: no transfer either way.
/// - Otherwise the newer `modifiedAt` wins. Ties are broken by comparing
///   fingerprints, which is arbitrary but *identical on every device*, so two
///   devices that edited at the same instant still converge on one value.
/// - A delete is represented as a tombstone, which is just a record whose
///   `deleted` flag is set. Because it carries a timestamp, a delete beats an
///   older edit and an edit beats an older delete.
/// - Tombstones are dropped from *local* bookkeeping past `tombstoneRetention`,
///   so a device stops carrying around deletions it has long since propagated.
///   The CloudKit tombstone record itself is intentionally kept: it is one small
///   record per token the user has ever deleted, and discarding it would shrink
///   the window in which a deletion is protected against a device that was
///   offline for longer than the retention period.
///
/// Pure by construction: no I/O, no clock reads (callers pass `now`), so every
/// branch below is directly assertable in a test.
nonisolated enum SyncMergeEngine {
    static let defaultTombstoneRetention: TimeInterval = 30 * 24 * 60 * 60

    static func merge(
        local: SyncLocalState,
        remote: [SyncRecord],
        now: Date = Date(),
        tombstoneRetention: TimeInterval = defaultTombstoneRetention
    ) -> SyncMergeOutcome {
        let localRecords = recordsByID(from: local)
        var remoteRecords: [String: SyncRecord] = [:]
        for record in remote {
            remoteRecords[record.id] = record
        }

        // A repeated id keeps its first copy, as `OTPDataStore.uniqueIDs` and
        // `recordsByID` do. `uniqueKeysWithValues:` trapped on one instead, and a
        // restored backup could put one in the store.
        var tokensByID = Dictionary(local.tokens.map { ($0.id.uuidString, $0) },
                                    uniquingKeysWith: { first, _ in first })
        var seenIDs = Set<String>()
        var order = local.tokens.map { $0.id.uuidString }.filter { seenIDs.insert($0).inserted }
        var tombstones = local.tombstones
        var uploads: [SyncRecord] = []
        var didAdoptRemoteChanges = false
        // Tombstones too old to keep replicating, collected after the loop so the
        // dictionary is never mutated while it is being walked.
        var collected: [String] = []

        /// True once a tombstone is old enough that we stop replicating it.
        func isCollected(_ record: SyncRecord) -> Bool {
            record.deleted && now.timeIntervalSince(record.modifiedAt) > tombstoneRetention
        }

        func adopt(_ record: SyncRecord) {
            didAdoptRemoteChanges = true
            if record.deleted {
                tokensByID.removeValue(forKey: record.id)
                order.removeAll { $0 == record.id }
                tombstones[record.id] = record.modifiedAt
            } else if let token = record.token {
                if tokensByID[record.id] == nil {
                    // New from another device: append so the existing on-screen
                    // order is not reshuffled under the user.
                    order.append(record.id)
                }
                tokensByID[record.id] = token
                tombstones.removeValue(forKey: record.id)
            }
        }

        for id in Set(localRecords.keys).union(remoteRecords.keys).sorted() {
            switch (localRecords[id], remoteRecords[id]) {
            case (nil, nil):
                continue

            case (nil, .some(let remote)):
                // Only iCloud knows this record. Skip collected tombstones so a
                // purged deletion is not re-imported on every sync.
                if isCollected(remote) { continue }
                adopt(remote)

            case (.some(let local), nil):
                if isCollected(local) {
                    tombstones.removeValue(forKey: id)
                } else {
                    uploads.append(local)
                }

            case (.some(let local), .some(let remote)):
                if local.fingerprint == remote.fingerprint { continue }
                switch resolve(local, against: remote) {
                case .keepLocal:
                    uploads.append(local)
                case .takeRemote:
                    adopt(remote)
                case .combined(let combined):
                    // Neither copy alone is right: the winner's content with the
                    // loser's further-along counter. It is a new write, so it
                    // goes up *and* is applied here.
                    adopt(combined)
                    uploads.append(combined)
                }
            }
        }

        for (id, deletedAt) in tombstones where now.timeIntervalSince(deletedAt) > tombstoneRetention {
            collected.append(id)
        }
        for id in collected {
            tombstones.removeValue(forKey: id)
        }

        return SyncMergeOutcome(
            tokens: order.compactMap { tokensByID[$0] },
            tombstones: tombstones,
            uploads: uploads,
            didAdoptRemoteChanges: didAdoptRemoteChanges
        )
    }

    /// How one conflict between two copies of a record settles.
    enum Resolution {
        /// This device's copy wins, and is what goes up.
        case keepLocal
        /// The other copy wins, and is applied here.
        case takeRemote
        /// Neither as it stands: the winner carrying the loser's higher counter.
        /// Both applied here *and* written up. See `combiningCounters`.
        case combined(SyncRecord)
    }

    /// The conflict rule for one record.
    ///
    /// The single place it is decided, so the merge and the CloudKit transport's
    /// per-record retry cannot disagree. They did: the counter rule lived only in
    /// the merge, and a push refused by the server — because another device wrote
    /// first — fell back to plain last-write-wins, which could write a lower
    /// counter over a higher one.
    static func resolve(_ local: SyncRecord, against remote: SyncRecord) -> Resolution {
        let localWon = wins(local, over: remote)
        let (winner, loser) = localWon ? (local, remote) : (remote, local)
        if let combined = combiningCounters(winner, loser) {
            return .combined(combined)
        }
        return localWon ? .keepLocal : .takeRemote
    }

    /// Last write wins on its own, without the counter rule. For tests of the
    /// timestamp and tie-break order; anything deciding a real conflict calls
    /// `resolve`.
    static func localWins(_ local: SyncRecord, over remote: SyncRecord) -> Bool {
        wins(local, over: remote)
    }

    /// The winner of a conflict between two counter-based copies, carrying the
    /// higher counter of the two — or `nil` when the winner already has it.
    ///
    /// Last write wins for everything else, but not for a counter. A counter only
    /// moves forward, and each value is a code that has been shown and may have
    /// been used: if one device spent codes 3 and 4, a rename made later on
    /// another device still at 3 must not put this token back on 3, because the
    /// service has already accepted that code and will refuse it.
    ///
    /// Stamped just after the newer of the two copies, so every device adopts it
    /// rather than tie-breaking against either, and two devices settling the same
    /// conflict make the same copy. Not stamped with the time of the merge: the
    /// copy is built from what this device had when the sync *started*, and an
    /// edit made here while the sync was out has to stay newer than it, or
    /// applying the result would quietly undo that edit.
    private static func combiningCounters(_ winner: SyncRecord, _ loser: SyncRecord) -> SyncRecord? {
        guard let winnerToken = winner.token, let loserToken = loser.token,
              winnerToken.kind == .hotp, loserToken.kind == .hotp,
              loserToken.counter > winnerToken.counter else { return nil }
        let stamp = max(winner.modifiedAt, loser.modifiedAt).addingTimeInterval(0.001)
        return .live(winnerToken.edited(counter: loserToken.counter, modifiedAt: stamp))
    }

    /// Last write wins; ties are broken deterministically so all devices agree.
    private static func wins(_ local: SyncRecord, over remote: SyncRecord) -> Bool {
        if local.modifiedAt != remote.modifiedAt {
            return local.modifiedAt > remote.modifiedAt
        }
        return local.fingerprint > remote.fingerprint
    }

    private static func recordsByID(from local: SyncLocalState) -> [String: SyncRecord] {
        var records: [String: SyncRecord] = [:]
        // The first copy of a repeated id, matching `tokensByID` in `merge`.
        for token in local.tokens where records[token.id.uuidString] == nil {
            records[token.id.uuidString] = .live(token)
        }
        // A live token always outranks a leftover tombstone for the same id.
        for (id, deletedAt) in local.tombstones where records[id] == nil {
            records[id] = .tombstone(id: id, deletedAt: deletedAt)
        }
        return records
    }
}

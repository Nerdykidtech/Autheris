import Foundation

/// The "Recently Deleted" buffer: a per-device undo for token deletion.
///
/// The trash is deliberately **local only**. Deleting a token still writes a
/// tombstone, so the deletion propagates to the user's other devices exactly as
/// it did before; the trash is only a second chance for the device the tap
/// happened on. Syncing it would mean a new record type, a new set of merge
/// rules for "deleted but still recoverable", and a way for one device to
/// re-create a token another device had already removed for good — none of which
/// buys anything the tombstone does not already give.
///
/// Pure and `nonisolated` so the retention and restore rules can be unit tested;
/// the Keychain I/O stays in `OTPDataStore`.
nonisolated enum TrashBin {

    /// How long a deleted token stays recoverable.
    static let defaultRetention: TimeInterval = 7 * 24 * 60 * 60

    /// The same window in whole days, for user-facing copy — derived rather than
    /// written twice so the text cannot drift from the behaviour.
    static var retentionDays: Int { Int(defaultRetention / (24 * 60 * 60)) }

    struct Entry: Equatable, Identifiable, Codable, Sendable {
        /// Deliberately not the token's own id: a token can be deleted, restored,
        /// and deleted again, which would otherwise produce two rows with one
        /// identity — and SwiftUI's `List` diffing does not tolerate that.
        let id: UUID
        let code: OTPCode
        let deletedAt: Date

        init(id: UUID = UUID(), code: OTPCode, deletedAt: Date) {
            self.id = id
            self.code = code
            self.deletedAt = deletedAt
        }

        /// When this entry stops being recoverable.
        func expiry(retention: TimeInterval = defaultRetention) -> Date {
            deletedAt.addingTimeInterval(retention)
        }
    }

    struct Sweep: Equatable {
        var kept: [Entry]
        var expired: [Entry]

        var didExpireAnything: Bool { !expired.isEmpty }
    }

    enum RestoreOutcome: Equatable {
        case restored(OTPCode)
        /// Something already holds this token's id or label+account, so restoring
        /// would create exactly the duplicate the rest of the app works to keep
        /// out.
        case collides
    }

    /// Splits the trash into what is still recoverable and what has aged out.
    ///
    /// An entry sitting exactly on the boundary is kept, matching the `>`
    /// convention `SyncMergeEngine` uses for tombstone retention.
    static func sweep(_ entries: [Entry],
                      now: Date,
                      retention: TimeInterval = defaultRetention) -> Sweep {
        var kept: [Entry] = []
        var expired: [Entry] = []
        for entry in entries {
            if now.timeIntervalSince(entry.deletedAt) > retention {
                expired.append(entry)
            } else {
                kept.append(entry)
            }
        }
        return Sweep(kept: kept, expired: expired)
    }

    /// The token to put back, or `.collides` when it would duplicate something.
    ///
    /// The returned copy is stamped with `now` instead of its original
    /// `modifiedAt`. That is what makes a restore an *edit*: it has to be a newer
    /// write than the tombstone the delete left behind, or the merge on the next
    /// sync would delete the token all over again.
    static func restore(_ entry: Entry, into existing: [OTPCode], at now: Date) -> RestoreOutcome {
        guard !collides(entry.code, with: existing) else { return .collides }
        return .restored(entry.code.edited(modifiedAt: now))
    }

    /// True when `code` duplicates something already stored — the same id, or the
    /// same label+account pair.
    ///
    /// Shared with `OTPDataStore.addCode` so the two cannot disagree about what
    /// "already there" means.
    static func collides(_ code: OTPCode, with existing: [OTPCode]) -> Bool {
        existing.contains {
            $0.id == code.id || ($0.label == code.label && $0.account == code.account)
        }
    }

    /// Most recently deleted first, which is the order a user expects to scan.
    static func newestFirst(_ entries: [Entry]) -> [Entry] {
        entries.sorted { $0.deletedAt > $1.deletedAt }
    }

    static func encode(_ entries: [Entry]) -> Data? {
        try? JSONEncoder().encode(entries)
    }

    static func decode(_ data: Data?) -> [Entry] {
        guard let data,
              let decoded = try? JSONDecoder().decode([Entry].self, from: data) else {
            return []
        }
        return decoded
    }
}

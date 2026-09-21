import Foundation

/// Where the device keeps its deletion tombstones, and how it chooses between the
/// current copy and the pre-Keychain one.
///
/// Tombstones belong in the Keychain, next to the tokens, because they have to
/// survive the same event the tokens do: an app reinstall. `UserDefaults` is
/// wiped when the app is deleted, but the Keychain is not — so a tombstone kept
/// in `UserDefaults` vanished on reinstall while the tokens it was suppressing
/// came back, and the next sync would re-import the deleted token from iCloud.
/// That is precisely the guarantee tombstones exist to provide (a delete must
/// beat a stale edit from a device that was offline), so losing them silently
/// un-deletes a token.
///
/// Pure and `nonisolated` so the precedence rules below can be unit tested; the
/// I/O stays in `OTPDataStore`.
nonisolated enum SyncTombstoneStore {

    /// What the device should load, and whether the legacy copy can now go.
    struct Resolution: Equatable {
        var tombstones: [String: Date]
        /// `true` when the value came from the pre-Keychain `UserDefaults` copy,
        /// which should now be removed.
        var removeLegacyCopy: Bool
    }

    /// Decodes a stored blob.
    ///
    /// Corrupt data yields no tombstones rather than throwing: a device that
    /// cannot read its own bookkeeping should sync conservatively, not refuse to
    /// start. The cost is bounded — `SyncMergeEngine` drops tombstones past the
    /// retention window anyway.
    static func decode(_ data: Data?) -> [String: Date] {
        guard let data,
              let decoded = try? JSONDecoder().decode([String: Date].self, from: data) else {
            return [:]
        }
        return decoded
    }

    static func encode(_ tombstones: [String: Date]) -> Data? {
        try? JSONEncoder().encode(tombstones)
    }

    /// Picks between the Keychain copy and the legacy `UserDefaults` copy.
    ///
    /// The Keychain wins whenever the item exists at all. A *present but empty*
    /// Keychain value is not the same as a missing one: it means "this device has
    /// no tombstones", and falling back to `UserDefaults` there would resurrect
    /// deletions that had already been fully propagated.
    static func resolve(keychain: Data?, legacyDefaults: Data?) -> Resolution {
        if keychain != nil {
            return Resolution(tombstones: decode(keychain),
                              removeLegacyCopy: legacyDefaults != nil)
        }

        guard legacyDefaults != nil else {
            return Resolution(tombstones: [:], removeLegacyCopy: false)
        }

        // First launch after upgrading: adopt what the old build left behind.
        return Resolution(tombstones: decode(legacyDefaults), removeLegacyCopy: true)
    }
}

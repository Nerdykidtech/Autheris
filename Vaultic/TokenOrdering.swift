import Foundation

/// How the token list is ordered.
///
/// Two separate things are going on, and only one of them syncs:
///
/// - **Pinning** is a property of a code (`OTPCode.isPinned`) and therefore
///   syncs like any other edit. Pinned codes sort to the top.
/// - **Manual order** is per-device, like arranging app icons. It is just the
///   order of `OTPDataStore.codes`, which is persisted and already survives a
///   sync because `SyncMergeEngine` keeps local order and only appends records it
///   has never seen. Deliberately *not* synced: a `sortIndex` field would mean a
///   single drag rewrites many tokens, bumping each `modifiedAt` and triggering a
///   large upload — and a concurrent edit on another device could then silently
///   win and drop the reorder.
///
/// Pure and `nonisolated` so both rules are unit testable; the store keeps the
/// array, this decides what order it is presented in.
nonisolated enum TokenOrdering {

    /// The order the list is shown in: pinned first, each group keeping its
    /// existing relative order.
    ///
    /// Idempotent, so a caller may normalise with it freely.
    static func displayed(_ tokens: [OTPCode]) -> [OTPCode] {
        tokens.filter(\.isPinned) + tokens.filter { !$0.isPinned }
    }

    /// Applies a SwiftUI `.onMove` to the list, expressed in the offsets of what
    /// the list is showing.
    ///
    /// `offsets` and `destination` must index `displayed(tokens)` — the array the
    /// caller rendered — which is why the input is normalised first. The result is
    /// normalised again, which is what makes dropping an unpinned code above a
    /// pinned one settle just below it instead of appearing to snap back.
    static func moving(_ tokens: [OTPCode], offsets: IndexSet, destination: Int) -> [OTPCode] {
        displayed(moved(displayed(tokens), offsets: offsets, destination: destination))
    }

    /// `Array.move(fromOffsets:toOffset:)` semantics, implemented here so this
    /// file needs no SwiftUI import.
    ///
    /// `destination` is an insertion point in the array *before* the moved
    /// elements are taken out, so it shifts down by however many removed elements
    /// it sat after.
    private static func moved(_ tokens: [OTPCode], offsets: IndexSet, destination: Int) -> [OTPCode] {
        let indices = offsets.sorted()
        guard !indices.isEmpty,
              indices.allSatisfy({ tokens.indices.contains($0) }) else { return tokens }

        let carried = indices.map { tokens[$0] }

        var remaining = tokens
        // Descending, so earlier removals cannot shift the indices still to come.
        for index in indices.reversed() {
            remaining.remove(at: index)
        }

        let shift = indices.filter { $0 < destination }.count
        let insertionPoint = min(max(destination - shift, 0), remaining.count)
        remaining.insert(contentsOf: carried, at: insertionPoint)
        return remaining
    }
}

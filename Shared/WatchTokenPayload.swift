import Foundation

/// The one thing the iPhone and the watch have to agree on: how a set of tokens
/// is spelled when it crosses `WatchConnectivity`.
///
/// Deliberately its own type rather than "just send `[OTPCode]`". Three reasons:
///
/// - **It is versioned.** The two apps ship in one bundle but can still be at
///   different versions — a watch app is updated by the Watch app, not by the
///   phone — so a watch running an older build ignores a payload it cannot
///   honour instead of decoding it into something wrong.
/// - **It is time-stamped.** The relay has two transports (an application context
///   and, for oversized lists, a file transfer). Nothing guarantees the order the
///   watch sees them in, so the payload carries the moment the phone sent it and
///   the watch applies whichever is newest. This is the same last-write-wins rule
///   `SyncMergeEngine` already uses for iCloud, and for the same reason.
/// - **It is one place.** Keys inside a `WCSession` dictionary are strings, and a
///   typo there does not fail to compile — it just sends a dictionary whose other
///   side finds nothing. The same failure `CloudKitTokenSyncService.Field` exists
///   to prevent.
///
/// Pure and `nonisolated` so both halves of the contract are unit testable from
/// `VaulticTests`, which is where the round trip is asserted.
nonisolated enum WatchTokenPayload {

    /// Bumped whenever the meaning of anything below changes. A receiver only
    /// accepts a version it knows.
    static let version = 1

    /// Keys inside the `WCSession` application-context dictionary.
    static let versionKey = "autherisPayloadVersion"
    static let tokensKey = "autherisTokens"

    /// The documented ceiling on a `WCSession` application context.
    ///
    /// The system rejects an oversized context rather than truncating it, which is
    /// why `applicationContext(for:)` returns `nil` past this point instead of
    /// letting `WCSession` throw: the caller needs to know to take the
    /// file-transfer route, not discover it from an error.
    static let maximumContextBytes = 65 * 1024

    /// The budget the token blob itself gets, leaving room for the envelope
    /// around it and for the property-list wrapping `WCSession` adds.
    static let contextByteBudget = maximumContextBytes - 1024

    /// A payload that has been received and understood.
    struct Decoded: Equatable, Sendable {
        /// When the phone sent it. The watch applies the newest it has seen.
        let sentAt: Date
        let tokens: [OTPCode]
    }

    // MARK: - Encoding

    /// The tokens, as JSON.
    ///
    /// JSON rather than a property list because the application context *itself*
    /// has to be a property list, so the tokens travel inside it as a single
    /// `Data` value — and JSON keeps that blob small.
    static func encode(_ tokens: [OTPCode], sentAt: Date = Date()) throws -> Data {
        try JSONEncoder().encode(Envelope(version: version, sentAt: sentAt, tokens: tokens))
    }

    /// The application context for a set of tokens, ready for
    /// `WCSession.updateApplicationContext(_:)`.
    ///
    /// - Returns: `nil` when the encoded tokens do not fit the context budget, so
    ///   the caller knows to take the file-transfer route instead of asking
    ///   `WCSession` to reject the update. The `sentAt` is passed in rather than
    ///   taken here so both transports carry the same stamp and cannot race.
    static func applicationContext(for tokens: [OTPCode], sentAt: Date = Date()) -> [String: Any]? {
        guard let blob = try? encode(tokens, sentAt: sentAt), blob.count <= contextByteBudget else { return nil }
        return [versionKey: version, tokensKey: blob]
    }

    // MARK: - Decoding

    /// The tokens in a received application context, or `nil` when there are none
    /// to be had.
    ///
    /// Returns `nil` — rather than an empty array — for a payload whose version
    /// this build does not understand, because "I do not know what this is" and
    /// "you have no codes" must not collapse into each other: the watch has to be
    /// able to keep showing what it already had.
    static func decode(applicationContext context: [String: Any]) -> Decoded? {
        guard let blob = context[tokensKey] as? Data else { return nil }
        return decode(blob)
    }

    /// The payload in a blob received by either transport.
    static func decode(_ blob: Data) -> Decoded? {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: blob),
              envelope.version == version else { return nil }
        return Decoded(sentAt: envelope.sentAt, tokens: envelope.tokens)
    }

    /// Whether `candidate` is worth applying over what was last applied.
    ///
    /// `>=` rather than `>`, so re-sending an unchanged list at the same instant
    /// is applied rather than ignored, and so a payload with no predecessor is
    /// always accepted (`appliedAt` starts at `.distantPast`). Kept here rather
    /// than inline in the view so the rule is asserted by a test.
    static func isNewer(_ candidate: Decoded, than appliedAt: Date) -> Bool {
        candidate.sentAt >= appliedAt
    }

    /// The wire form. A separate type from its contents so the version and stamp
    /// cannot be forgotten at a call site.
    private struct Envelope: Codable {
        let version: Int
        let sentAt: Date
        let tokens: [OTPCode]
    }
}

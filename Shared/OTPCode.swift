import Foundation

nonisolated struct OTPCode: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let label: String
    let account: String
    let secret: String
    let algorithm: OTPAlgorithm
    let digits: Int
    let period: Int
    /// Whether the code is time-based or counter-based.
    ///
    /// `period` is only meaningful for a time-based code and `counter` only for a
    /// counter-based one, and both are kept rather than collapsed into one optional
    /// so that switching a token's kind — which the app deliberately does not offer
    /// — could not lose the other's value. See `OTPKind`.
    let kind: OTPKind
    /// How many codes this token has produced. Only meaningful when `kind` is
    /// `.hotp`; a counter-based code stays valid until the counter moves, so this
    /// is user state that has to persist and sync rather than a derived value.
    ///
    /// Capped at `OTPCode.maximumCounter`, which is the largest counter the CloudKit
    /// `Int64` field can carry back — a value beyond it would be written as one
    /// number and read as another. Tokens persisted before counter-based codes
    /// existed decode as `0`; see `init(from:)`.
    let counter: UInt64
    /// Optional `RRGGBB` hex (no `#`) for the countdown ring; `nil` uses issuer branding color.
    let timerRingHex: String?
    /// Whether the user has pinned this code to the top of the list.
    ///
    /// The pin itself syncs, because it is a property of the code. The *manual
    /// order* does not — see `TokenOrdering`. Tokens persisted before pinning
    /// existed decode as `false`; see `init(from:)`.
    let isPinned: Bool
    /// Wall-clock time of the last local edit to this token.
    ///
    /// This is the "last write" used by the iCloud sync conflict rule: when the
    /// same token exists on two devices with different contents, the newer
    /// `modifiedAt` wins. It travels with the token through `Codable`, so it
    /// survives backup/restore and QR export/import.
    ///
    /// Tokens persisted before sync existed decode as `Date.distantPast`, so
    /// they lose to any genuinely edited copy — see `init(from:)`.
    let modifiedAt: Date

    /// The largest counter a token may hold, and the reason it is not `UInt64.max`.
    ///
    /// The iCloud record stores the counter as an `Int64`, so a larger value would
    /// survive locally and come back as a different number — a wrong code with no
    /// error anywhere. Parsing an `otpauth://` URL clamps to this for the same
    /// reason: the input is a string a stranger wrote.
    static let maximumCounter = UInt64(Int64.max)

    init(id: UUID = UUID(), label: String, account: String, secret: String, algorithm: OTPAlgorithm = .sha1, digits: Int = 6, period: Int = 30, kind: OTPKind = .totp, counter: UInt64 = 0, timerRingHex: String? = nil, isPinned: Bool = false, modifiedAt: Date = Date()) {
        self.id = id
        self.label = label
        self.account = account
        self.secret = secret
        self.algorithm = algorithm
        self.digits = digits
        self.period = period
        self.kind = kind
        self.counter = min(counter, Self.maximumCounter)
        self.timerRingHex = timerRingHex
        self.isPinned = isPinned
        self.modifiedAt = modifiedAt
    }

    /// The values the code is really generated with.
    ///
    /// A stored `digits` or `period` can be malformed — it comes straight from an
    /// `otpauth://` URL or a foreign backup, neither of which validates it, and a
    /// token saved by an earlier build may already hold a bad one. `HomeView` reads
    /// these for the countdown so the ring cannot disagree with the code it is
    /// counting down for.
    var effectiveDigits: Int { OTPGenerator.effectiveDigits(digits) }
    var effectivePeriod: Int { OTPGenerator.effectivePeriod(period) }

    /// Whether this token's code is replaced by the clock (`true`) or by the user
    /// asking for the next one (`false`).
    ///
    /// Spelled as a property because "is there a countdown" is a question the views
    /// ask in several places, and each of them asking it as `kind == .totp` is how
    /// one of them ends up asking the other way round.
    var isTimeBased: Bool { kind == .totp }

    var currentCode: String { code(at: Date()) }

    /// The code shown at `now`. A counter-based code ignores the time.
    func code(at now: Date) -> String {
        switch kind {
        case .totp:
            return OTPGenerator.generateOTP(secret: secret, algorithm: algorithm,
                                             digits: effectiveDigits, period: effectivePeriod,
                                             now: now)
        case .hotp:
            return OTPGenerator.generateHOTP(secret: secret, algorithm: algorithm,
                                              digits: effectiveDigits, counter: counter)
        }
    }

    /// Returns a copy with the content replaced and `modifiedAt` bumped to now.
    ///
    /// Edit paths should go through this so sync always sees a stamp newer than
    /// the record being replaced.
    func edited(
        label: String? = nil,
        account: String? = nil,
        secret: String? = nil,
        algorithm: OTPAlgorithm? = nil,
        digits: Int? = nil,
        period: Int? = nil,
        kind: OTPKind? = nil,
        counter: UInt64? = nil,
        timerRingHex: String?? = nil,
        isPinned: Bool? = nil,
        modifiedAt: Date = Date()
    ) -> OTPCode {
        OTPCode(
            id: id,
            label: label ?? self.label,
            account: account ?? self.account,
            secret: secret ?? self.secret,
            algorithm: algorithm ?? self.algorithm,
            digits: digits ?? self.digits,
            period: period ?? self.period,
            kind: kind ?? self.kind,
            counter: counter ?? self.counter,
            timerRingHex: timerRingHex ?? self.timerRingHex,
            isPinned: isPinned ?? self.isPinned,
            modifiedAt: modifiedAt
        )
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id, label, account, secret, algorithm, digits, period, kind, counter, timerRingHex, isPinned, modifiedAt
    }

    /// Hand-written so `modifiedAt` may be absent from previously persisted JSON
    /// without failing the whole decode. `algorithm`, `digits`, `period`, `kind`,
    /// `counter`, `timerRingHex` and `isPinned` are tolerated as missing for the
    /// same reason: a key added by a later release must not make an existing vault
    /// unreadable.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        account = try container.decode(String.self, forKey: .account)
        secret = try container.decode(String.self, forKey: .secret)
        algorithm = try container.decodeIfPresent(OTPAlgorithm.self, forKey: .algorithm) ?? .sha1
        digits = try container.decodeIfPresent(Int.self, forKey: .digits) ?? 6
        period = try container.decodeIfPresent(Int.self, forKey: .period) ?? 30
        // Absent on every token written before counter-based codes existed, which is
        // exactly what `.totp` / `0` mean. An unrecognised `kind` — a value from a
        // newer build, say — also falls back to time-based rather than failing the
        // decode, because refusing to read the vault at all is the worse answer.
        kind = OTPKind(rawValue: try container.decodeIfPresent(String.self, forKey: .kind) ?? "") ?? .totp
        counter = min(try container.decodeIfPresent(UInt64.self, forKey: .counter) ?? 0, Self.maximumCounter)
        timerRingHex = try container.decodeIfPresent(String.self, forKey: .timerRingHex)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? .distantPast
    }
}

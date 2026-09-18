import Foundation

nonisolated struct OTPCode: Identifiable, Codable, Sendable {
    let id: UUID
    let label: String
    let account: String
    let secret: String
    let algorithm: OTPAlgorithm
    let digits: Int
    let period: Int
    /// Optional `RRGGBB` hex (no `#`) for the countdown ring; `nil` uses issuer branding color.
    let timerRingHex: String?
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

    init(id: UUID = UUID(), label: String, account: String, secret: String, algorithm: OTPAlgorithm = .sha1, digits: Int = 6, period: Int = 30, timerRingHex: String? = nil, modifiedAt: Date = Date()) {
        self.id = id
        self.label = label
        self.account = account
        self.secret = secret
        self.algorithm = algorithm
        self.digits = digits
        self.period = period
        self.timerRingHex = timerRingHex
        self.modifiedAt = modifiedAt
    }

    var currentCode: String {
        OTPGenerator.generateOTP(secret: secret, algorithm: algorithm, digits: digits, period: period)
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
        timerRingHex: String?? = nil,
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
            timerRingHex: timerRingHex ?? self.timerRingHex,
            modifiedAt: modifiedAt
        )
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id, label, account, secret, algorithm, digits, period, timerRingHex, modifiedAt
    }

    /// Hand-written so `modifiedAt` may be absent from previously persisted JSON
    /// without failing the whole decode. `algorithm`, `digits`, `period` and
    /// `timerRingHex` are tolerated as missing for the same reason.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        account = try container.decode(String.self, forKey: .account)
        secret = try container.decode(String.self, forKey: .secret)
        algorithm = try container.decodeIfPresent(OTPAlgorithm.self, forKey: .algorithm) ?? .sha1
        digits = try container.decodeIfPresent(Int.self, forKey: .digits) ?? 6
        period = try container.decodeIfPresent(Int.self, forKey: .period) ?? 30
        timerRingHex = try container.decodeIfPresent(String.self, forKey: .timerRingHex)
        modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? .distantPast
    }
}

import Foundation

/// Errors surfaced when importing a backup from another authenticator app.
enum ExternalImportError: LocalizedError {
    case unsupportedFormat
    case encryptedAegisVault
    case noTokens

    var errorDescription: String? {
        // `String(localized:)` on every one of these. They used to be bare literals,
        // which is a shape nothing checks: the extractor only picks up a string it
        // recognises as localizable, and the coverage test looks for the same call
        // shapes — so these three shipped in English in all seven languages, in the
        // one place a user is already confused (a backup that would not import).
        switch self {
        case .unsupportedFormat:
            return String(localized: "This file isn't a supported Aegis, andOTP, or 2FAS export.")
        case .encryptedAegisVault:
            return String(localized: "Encrypted Aegis exports aren't supported yet. Export an unencrypted Aegis vault instead.")
        case .noTokens:
            return String(localized: "No compatible one-time-password tokens were found in this file.")
        }
    }
}

/// Imports unencrypted backups from other authenticator apps:
/// - Aegis (`db.entries[].info`)
/// - andOTP (JSON array)
/// - 2FAS (`services[]`)
///
/// Both `TOTP` and `HOTP` entries are imported, with the counter the export
/// carries. Steam, MOTP and Yandex entries are still skipped: they are neither of
/// the two the app can generate, and importing one as a TOTP token would hand back
/// codes that never work.
///
/// 2FAS is the exception within the exception — its HOTP entries are skipped,
/// because this parser reads the counter for Aegis and andOTP from the field those
/// formats document (`counter`, a sibling of the type) and the 2FAS export's
/// equivalent is not documented anywhere this project can check. Skipping it is the
/// behaviour it already had; guessing a field name would replace a skip with an
/// import whose counter silently starts at 0, which is a wrong code rather than a
/// missing one.
enum ExternalImportParser {
    static func parse(data: Data) throws -> [OTPCode] {
        let json = try JSONSerialization.jsonObject(with: data)

        if let root = json as? [String: Any] {
            if root["db"] != nil {
                return try parseAegis(root)
            }
            if root["services"] != nil {
                return try parseTwoFAS(root)
            }
        }

        if let entries = json as? [[String: Any]] {
            return try parseAndOTP(entries)
        }

        throw ExternalImportError.unsupportedFormat
    }

    // MARK: - Aegis

    private static func parseAegis(_ root: [String: Any]) throws -> [OTPCode] {
        // Unencrypted vaults have a null/empty header, or — as Aegis actually writes
        // them — `{"slots": null, "params": null}`. Anything with a value in it means
        // the export is encrypted, which we don't support yet.
        if let header = root["header"], !(header is NSNull) {
            if let headerDict = header as? [String: Any],
               headerDict.values.allSatisfy({ $0 is NSNull }) {
                // plain
            } else {
                throw ExternalImportError.encryptedAegisVault
            }
        }

        guard let db = root["db"] as? [String: Any],
              let entries = db["entries"] as? [[String: Any]] else {
            throw ExternalImportError.unsupportedFormat
        }

        var tokens: [OTPCode] = []
        for entry in entries {
            // Aegis spells the kind in `type`, lowercased. The counter is read from
            // either place it can sit — beside the type, or inside `info` with the
            // algorithm and digit count — because the two exports differ on this and a
            // counter read from the wrong one is 0, which is a wrong code rather than
            // an obviously missing field. Reading both costs nothing: the value is
            // only consulted for a counter-based entry.
            guard let kind = kind(fromType: entry["type"] as? String) else { continue }

            guard let info = entry["info"] as? [String: Any],
                  let secret = info["secret"] as? String,
                  OTPGenerator.isValidSecret(secret) else { continue }

            let name = (entry["name"] as? String) ?? ""
            let issuer = (entry["issuer"] as? String) ?? ""
            let label = issuer.isEmpty ? name : issuer
            let account = issuer.isEmpty ? "" : name

            tokens.append(OTPCode(
                label: label.isEmpty ? "Imported" : label,
                account: account,
                secret: secret,
                algorithm: algorithm(from: info["algo"] as? String),
                digits: (info["digits"] as? Int) ?? 6,
                period: (info["period"] as? Int) ?? 30,
                kind: kind,
                counter: counter(from: entry["counter"] ?? info["counter"], for: kind)
            ))
        }
        return deduplicated(tokens)
    }

    // MARK: - andOTP

    private static func parseAndOTP(_ entries: [[String: Any]]) throws -> [OTPCode] {
        var tokens: [OTPCode] = []
        for entry in entries {
            guard let kind = kind(fromType: entry["type"] as? String) else { continue }

            guard let secret = entry["secret"] as? String,
                  OTPGenerator.isValidSecret(secret) else { continue }

            let issuer = (entry["issuer"] as? String) ?? ""
            let accountLabel = (entry["label"] as? String) ?? ""
            let label = issuer.isEmpty ? accountLabel : issuer
            let account = issuer.isEmpty ? "" : accountLabel

            tokens.append(OTPCode(
                label: label.isEmpty ? "Imported" : label,
                account: account,
                secret: secret,
                algorithm: algorithm(from: entry["algorithm"] as? String),
                digits: (entry["digits"] as? Int) ?? 6,
                period: (entry["period"] as? Int) ?? 30,
                kind: kind,
                counter: counter(from: entry["counter"], for: kind)
            ))
        }
        return deduplicated(tokens)
    }

    // MARK: - 2FAS

    private static func parseTwoFAS(_ root: [String: Any]) throws -> [OTPCode] {
        guard let services = root["services"] as? [[String: Any]] else {
            throw ExternalImportError.unsupportedFormat
        }

        var tokens: [OTPCode] = []
        for service in services {
            let otp = service["otp"] as? [String: Any] ?? [:]
            // 2FAS's counter field for a HOTP entry is left alone: this parser has
            // no documentation for it to check against, and importing the entry
            // with a counter of 0 would replace a skip with codes that never work.
            // See the note on this type.
            let tokenType = (otp["tokenType"] as? String) ?? "TOTP"
            guard tokenType.uppercased() == "TOTP" else { continue }

            guard let secret = service["secret"] as? String,
                  OTPGenerator.isValidSecret(secret) else { continue }

            let name = (service["name"] as? String) ?? ""
            tokens.append(OTPCode(
                label: name.isEmpty ? "Imported" : name,
                account: "",
                secret: secret,
                algorithm: algorithm(from: otp["algorithm"] as? String),
                digits: (otp["digits"] as? Int) ?? 6,
                period: (otp["period"] as? Int) ?? 30
            ))
        }
        return deduplicated(tokens)
    }

    // MARK: - Helpers

    /// The kind of code an export's entry names, or `nil` for one this app cannot
    /// generate.
    ///
    /// A missing or empty value is time-based, which is what those formats mean by
    /// saying nothing and what nearly every entry is. Steam, MOTP and Yandex are
    /// refused rather than rounded down: each is its own algorithm, and a token that
    /// produced plausible-looking codes that never work is worse than one that is
    /// not imported at all.
    private static func kind(fromType raw: String?) -> OTPKind? {
        switch (raw ?? "").uppercased() {
        case "TOTP", "":
            return .totp
        case "HOTP":
            return .hotp
        default:
            return nil
        }
    }

    /// The counter a counter-based entry starts at.
    ///
    /// Absent reads as `0`, which is where a counter-based token begins, and the
    /// value is clamped to what the iCloud record can carry back for the same reason
    /// `OTPAuthURLParser` clamps it — an export is a file from somewhere else.
    private static func counter(from raw: Any?, for kind: OTPKind) -> UInt64 {
        guard kind == .hotp, let number = raw as? NSNumber else { return 0 }
        return min(UInt64(max(0, number.int64Value)), OTPCode.maximumCounter)
    }

    private static func algorithm(from raw: String?) -> OTPAlgorithm {
        switch (raw ?? "").uppercased() {
        case "SHA256", "SHA-256":
            return .sha256
        case "SHA512", "SHA-512":
            return .sha512
        default:
            return .sha1
        }
    }

    private static func deduplicated(_ tokens: [OTPCode]) -> [OTPCode] {
        var seen = Set<String>()
        return tokens.filter { token in
            seen.insert("\(token.label.lowercased())|\(token.account.lowercased())").inserted
        }
    }
}

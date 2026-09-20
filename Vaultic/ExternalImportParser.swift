import Foundation

/// Errors surfaced when importing a backup from another authenticator app.
enum ExternalImportError: LocalizedError {
    case unsupportedFormat
    case encryptedAegisVault
    case noTokens

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "This file isn't a supported Aegis, andOTP, or 2FAS export."
        case .encryptedAegisVault:
            return "Encrypted Aegis exports aren't supported yet. Export an unencrypted Aegis vault instead."
        case .noTokens:
            return "No compatible TOTP tokens were found in this file."
        }
    }
}

/// Imports unencrypted backups from other authenticator apps:
/// - Aegis (`db.entries[].info`)
/// - andOTP (JSON array)
/// - 2FAS (`services[]`)
///
/// Autheris only supports TOTP, so HOTP/Steam/MOTP/Yandex entries are skipped.
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
        // Unencrypted vaults have a null/empty header. Anything else means the
        // export is encrypted, which we don't support yet.
        if let header = root["header"], !(header is NSNull) {
            if let headerDict = header as? [String: Any], headerDict.isEmpty {
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
            let type = (entry["type"] as? String) ?? "totp"
            guard type.lowercased() == "totp" else { continue }

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
                period: (info["period"] as? Int) ?? 30
            ))
        }
        return deduplicated(tokens)
    }

    // MARK: - andOTP

    private static func parseAndOTP(_ entries: [[String: Any]]) throws -> [OTPCode] {
        var tokens: [OTPCode] = []
        for entry in entries {
            let type = (entry["type"] as? String) ?? "TOTP"
            guard type.uppercased() == "TOTP" else { continue }

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
                period: (entry["period"] as? Int) ?? 30
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

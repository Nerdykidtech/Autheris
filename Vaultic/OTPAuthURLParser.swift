import Foundation

/// Parsed fields from an `otpauth://` URL.
struct ParsedOTPAuth: Equatable {
    let label: String
    let account: String
    let secret: String
    let algorithm: OTPAlgorithm
    let digits: Int
    let period: Int
}

/// Parses the standard `otpauth://totp/...` setup URLs that iOS hands to the
/// app when the user picks "Set Up Codes In → Autheris".
enum OTPAuthURLParser {
    static func parse(_ url: URL) -> ParsedOTPAuth? {
        guard url.scheme?.lowercased() == "otpauth" else { return nil }

        // Format: otpauth://totp/Service:Account?secret=...&issuer=...
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        var label = ""
        var account = ""

        if path.contains(":") {
            let parts = path.components(separatedBy: ":")
            label = parts.first ?? ""
            account = parts.dropFirst().joined(separator: ":")
        } else if !path.isEmpty {
            label = path
        }

        var secret = ""
        var algorithm: OTPAlgorithm = .sha1
        var digits = 6
        var period = 30

        if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            for item in items {
                switch item.name.lowercased() {
                case "secret":
                    secret = item.value ?? ""
                case "algorithm":
                    switch (item.value ?? "").uppercased() {
                    case "SHA256", "SHA-256":
                        algorithm = .sha256
                    case "SHA512", "SHA-512":
                        algorithm = .sha512
                    default:
                        algorithm = .sha1
                    }
                case "digits":
                    digits = Int(item.value ?? "") ?? 6
                case "period":
                    period = Int(item.value ?? "") ?? 30
                case "issuer":
                    if let issuer = item.value, !issuer.isEmpty {
                        label = issuer
                    }
                default:
                    break
                }
            }
        }

        label = label.removingPercentEncoding ?? label
        account = account.removingPercentEncoding ?? account
        secret = secret.removingPercentEncoding ?? secret

        guard !label.isEmpty, !secret.isEmpty else { return nil }
        return ParsedOTPAuth(
            label: label,
            account: account,
            secret: secret,
            algorithm: algorithm,
            digits: digits,
            period: period
        )
    }
}

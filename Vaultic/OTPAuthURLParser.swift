import Foundation

/// Parsed fields from an `otpauth://` URL.
struct ParsedOTPAuth: Equatable {
    let label: String
    let account: String
    let secret: String
    let algorithm: OTPAlgorithm
    let digits: Int
    let period: Int
    /// Time-based or counter-based, from the URL's host.
    let kind: OTPKind
    /// The counter a counter-based URL starts at. Always `0` for a time-based one,
    /// and `0` for an HOTP URL that names no counter, which is the RFC 4226 default.
    let counter: UInt64
}

/// Parses the standard `otpauth://totp/...` setup URLs that iOS hands to the
/// app when the user picks "Set Up Codes In → Autheris".
enum OTPAuthURLParser {

    /// The token in a string somebody pasted or typed, when it is a setup link.
    ///
    /// The manual form takes a setup *key*, and a service that hands out a link
    /// instead — most of them do, on their website — left the user with a field that
    /// rejected it: a URL is not Base32, so it failed validation with nothing to
    /// explain why. Reading it as the link it is costs one parse and puts it on the
    /// same path as a scanned QR code, kind and counter included.
    ///
    /// Returns `nil` for anything that is not an `otpauth://` URL — including a bare
    /// Base32 key, which the caller handles, and an `autheris://import` transfer
    /// link, which carries a whole vault rather than one token and belongs to the
    /// import flow instead.
    static func parseLink(_ text: String) -> ParsedOTPAuth? {
        // Links arrive with trailing whitespace more often than not: copied out of a
        // web page, or pasted out of a message that wrapped it.
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              url.scheme?.lowercased() == "otpauth" else { return nil }
        return parse(url)
    }

    static func parse(_ url: URL) -> ParsedOTPAuth? {
        guard url.scheme?.lowercased() == "otpauth" else { return nil }

        // Format: otpauth://totp/Service:Account?secret=...&issuer=...
        //
        // The host is the `totp`/`hotp` part, and it is the only place a setup URL
        // states which kind it is. Reading it is the difference between a working
        // code and a plausible-looking wrong one: before this, an `otpauth://hotp/`
        // URL parsed as a time-based token and its codes were silently rejected by
        // the service that issued it.
        let kind = OTPKind(urlHost: url.host)

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
        var counter: UInt64 = 0

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
                case "counter":
                    // Only meaningful for a counter-based token, and ignored
                    // elsewhere: a time-based code has no counter to honour, and
                    // carrying one over would be inventing state the service never
                    // asked for.
                    //
                    // Clamped to what the iCloud record's `Int64` field can carry
                    // back, rather than trusted, because this is a number a stranger
                    // put in a QR code: a value beyond it would be written and read
                    // back as something else, which is a wrong code with nothing to
                    // notice it.
                    if let raw = item.value, let parsed = UInt64(raw) {
                        counter = min(parsed, OTPCode.maximumCounter)
                    }
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
            period: period,
            kind: kind,
            counter: kind == .hotp ? counter : 0
        )
    }
}

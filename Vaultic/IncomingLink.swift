import Foundation

/// What an `autheris://import`, `otpauth://` or `otpauth-migration://` link
/// carries, decoded but not yet acted on.
///
/// Any installed app, and any web page the user agrees to open, can hand Autheris
/// one of these links. So parsing one must never touch the vault: the codes it
/// yields are shown to the user, who accepts or rejects them, and only once App
/// Lock has been passed. `ImportConfirmationView` is the one place they are
/// written. See GHSA-75h3-q43q-9338, where all three schemes used to import on
/// arrival, behind a locked app.
nonisolated enum IncomingLink: Equatable {
    /// Codes waiting for the user to confirm them. Never empty.
    case tokens([OTPCode])
    /// The link was one of ours but could not be read.
    case failure(title: String, message: String)

    /// `nil` when the URL is not one Autheris handles at all.
    static func parse(_ url: URL) -> IncomingLink? {
        switch url.scheme?.lowercased() {
        case "otpauth":
            return parseOTPAuth(url)
        case "otpauth-migration":
            return parseMigration(url)
        case "autheris" where url.host?.lowercased() == "import":
            return parseAutherisImport(url)
        default:
            return nil
        }
    }

    /// The codes in `incoming` that are not already in `existing`, matched the
    /// way the rest of the app matches them: by label and account together.
    static func newTokens(_ incoming: [OTPCode], existing: [OTPCode]) -> [OTPCode] {
        incoming.filter { candidate in
            !existing.contains { $0.label == candidate.label && $0.account == candidate.account }
        }
    }

    // MARK: - Schemes

    private static func parseOTPAuth(_ url: URL) -> IncomingLink {
        guard let parsed = OTPAuthURLParser.parse(url) else {
            return .failure(
                title: String(localized: "Couldn't Add Code"),
                message: String(localized: "That verification-code link isn't in the expected otpauth format.")
            )
        }

        guard OTPGenerator.isValidSecret(parsed.secret) else {
            return .failure(
                title: String(localized: "Couldn't Add Code"),
                message: String(localized: "The setup key in that link isn't a valid Base32 secret.")
            )
        }

        return .tokens([OTPCode(
            label: parsed.label,
            account: parsed.account,
            secret: parsed.secret,
            algorithm: parsed.algorithm,
            digits: parsed.digits,
            period: parsed.period,
            kind: parsed.kind,
            counter: parsed.counter
        )])
    }

    private static func parseMigration(_ url: URL) -> IncomingLink {
        guard let tokens = GoogleMigrationParser.parseMigrationURL(url.absoluteString), !tokens.isEmpty else {
            return .failure(
                title: String(localized: "Couldn't Add Codes"),
                message: String(localized: "Could not parse this Google Authenticator export.")
            )
        }
        return .tokens(tokens)
    }

    private static func parseAutherisImport(_ url: URL) -> IncomingLink {
        guard let dataString = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "data" })?.value,
              let data = decodeBase64URL(dataString),
              let tokens = decodeTokens(data),
              !tokens.isEmpty
        else {
            return .failure(
                title: String(localized: "Import Failed"),
                message: String(localized: "Could not parse the import data. The QR code may be corrupted or in an unsupported format.")
            )
        }
        return .tokens(tokens)
    }

    /// An Autheris export is either the current `ExportData` envelope or, from
    /// older versions, a bare array of codes.
    private static func decodeTokens(_ data: Data) -> [OTPCode]? {
        let decoder = JSONDecoder()
        if let export = try? decoder.decode(ExportData.self, from: data) {
            return export.tokens
        }
        return try? decoder.decode([OTPCode].self, from: data)
    }

    /// URL-safe Base64, with or without its padding.
    private static func decodeBase64URL(_ string: String) -> Data? {
        var standard = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - standard.count % 4) % 4
        standard += String(repeating: "=", count: padding)
        return Data(base64Encoded: standard)
    }
}

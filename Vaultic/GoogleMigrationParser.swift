import Foundation

/// Parses Google Authenticator export format (otpauth-migration).
/// Format: otpauth-migration://offline?data=<url-encoded-base64-protobuf>
/// See: https://github.com/qistoph/otp_export
enum GoogleMigrationParser {
    
    /// Parses an otpauth-migration URL string and returns OTPCode entries, or nil if not valid migration / parse failed.
    static func parseMigrationURL(_ urlString: String) -> [OTPCode]? {
        guard urlString.hasPrefix("otpauth-migration://"),
              let url = URL(string: urlString),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let dataParam = components.queryItems?.first(where: { $0.name == "data" })?.value,
              !dataParam.isEmpty else {
            return nil
        }
        guard let data = decodeMigrationData(dataParam) else { return nil }
        return parseMigrationPayload(data)
    }
    
    /// URL-decode then Base64-decode the `data` query parameter.
    /// Do NOT replace "+" with space — that's form-encoding; Base64 uses "+" as a valid character.
    /// See https://imrannazar.com/articles/degoogle-otp
    private static func decodeMigrationData(_ encoded: String) -> Data? {
        let urlDecoded = encoded.removingPercentEncoding ?? encoded
        // Base64 can be standard (+/) or URL-safe (-_); normalize to standard for decoding
        let base64 = urlDecoded
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
            .filter { $0.isLetter || $0.isNumber || $0 == "+" || $0 == "/" || $0 == "=" }
        guard !base64.isEmpty else { return nil }
        let padding = (4 - (base64.count % 4)) % 4
        let padded = base64 + String(repeating: "=", count: padding)
        return Data(base64Encoded: padded)
    }
    
    /// Parse MigrationPayload protobuf: repeated OtpParameters (field 1).
    private static func parseMigrationPayload(_ data: Data) -> [OTPCode]? {
        var tokens: [OTPCode] = []
        var offset = 0
        let bytes = [UInt8](data)
        
        while offset < bytes.count {
            guard let (tag, wireType) = readTag(bytes, offset: &offset) else { break }
            if tag == 1 && wireType == 2 {
                // Length-delimited: OtpParameters message
                guard let len = readVarint(bytes, offset: &offset),
                      offset + len <= bytes.count else { break }
                let msg = Data(bytes[offset..<(offset + len)])
                offset += len
                if let code = parseOtpParameters(msg) {
                    tokens.append(code)
                }
            } else {
                skipField(bytes, tag: tag, wireType: wireType, offset: &offset)
            }
        }
        return tokens.isEmpty ? nil : tokens
    }
    
    /// Parse OtpParameters message: secret(1), name(2), issuer(3), algorithm(4), digits(5), type(6), counter(7).
    private static func parseOtpParameters(_ data: Data) -> OTPCode? {
        var secretData: Data?
        var name: String?
        var issuer: String?
        var algorithm: OTPAlgorithm = .sha1
        var digits: Int = 6
        var type: Int = 2 // TOTP
        var counter: UInt64 = 0
        
        var offset = 0
        let bytes = [UInt8](data)
        
        while offset < bytes.count {
            guard let (tag, wireType) = readTag(bytes, offset: &offset) else { break }
            switch tag {
            case 1: // secret (bytes)
                if wireType == 2, let len = readVarint(bytes, offset: &offset), offset + len <= bytes.count {
                    secretData = Data(bytes[offset..<(offset + len)])
                    offset += len
                } else { skipField(bytes, tag: tag, wireType: wireType, offset: &offset) }
            case 2: // name (string)
                if wireType == 2, let len = readVarint(bytes, offset: &offset), offset + len <= bytes.count {
                    name = String(data: Data(bytes[offset..<(offset + len)]), encoding: .utf8)
                    offset += len
                } else { skipField(bytes, tag: tag, wireType: wireType, offset: &offset) }
            case 3: // issuer (string)
                if wireType == 2, let len = readVarint(bytes, offset: &offset), offset + len <= bytes.count {
                    issuer = String(data: Data(bytes[offset..<(offset + len)]), encoding: .utf8)
                    offset += len
                } else { skipField(bytes, tag: tag, wireType: wireType, offset: &offset) }
            case 4: // algorithm (varint): 1=SHA1, 2=SHA256, 3=SHA512
                if wireType == 0, let v = readVarint(bytes, offset: &offset) {
                    algorithm = (v == 2) ? .sha256 : (v == 3) ? .sha512 : .sha1
                } else { skipField(bytes, tag: tag, wireType: wireType, offset: &offset) }
            case 5: // digits (varint): 1=SIX=6, 2=EIGHT=8
                if wireType == 0, let v = readVarint(bytes, offset: &offset) {
                    digits = (v == 2) ? 8 : 6
                } else { skipField(bytes, tag: tag, wireType: wireType, offset: &offset) }
            case 6: // type (varint): 1=HOTP, 2=TOTP
                if wireType == 0, let v = readVarint(bytes, offset: &offset) {
                    type = v
                } else { skipField(bytes, tag: tag, wireType: wireType, offset: &offset) }
            case 7: // counter (varint/int64)
                if wireType == 0, let v = readVarint(bytes, offset: &offset) {
                    counter = UInt64(max(0, v))
                } else { skipField(bytes, tag: tag, wireType: wireType, offset: &offset) }
            default:
                skipField(bytes, tag: tag, wireType: wireType, offset: &offset)
            }
        }
        
        guard let secret = secretData, !secret.isEmpty else { return nil }
        let secretBase32 = OTPGenerator.encodeBase32(secret)
        guard OTPGenerator.isValidSecret(secretBase32) else { return nil }
        
        // name is "Issuer:Account" or "Account"; issuer can override label
        let label: String
        let account: String
        if let n = name?.trimmingCharacters(in: .whitespaces), !n.isEmpty {
            if n.contains(":") {
                let parts = n.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                label = String(parts[0]).trimmingCharacters(in: .whitespaces)
                account = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""
            } else {
                label = (issuer?.isEmpty == false) ? (issuer ?? n) : n
                account = (issuer?.isEmpty == false) ? n : ""
            }
        } else {
            label = issuer ?? "Imported"
            account = ""
        }
        
        // HOTP entries are imported rather than dropped. They used to be skipped
        // outright — this guard read `type == 2` — which meant a Google
        // Authenticator user with a counter-based account silently lost it on
        // import, with nothing on screen to say so.
        //
        // Anything that is not explicitly HOTP is time-based: 2 is TOTP, and 0
        // (the protobuf's "unspecified") is what an unset field decodes to, which
        // for a field Google itself always writes means the TOTP default.
        let kind: OTPKind = (type == 1) ? .hotp : .totp

        return OTPCode(
            label: label,
            account: account,
            secret: secretBase32,
            algorithm: algorithm,
            digits: digits,
            period: 30,
            kind: kind,
            // Only meaningful for HOTP; a TOTP entry carries no counter and
            // `OTPCode` ignores it.
            counter: kind == .hotp ? counter : 0
        )
    }
    
    private static func readTag(_ bytes: [UInt8], offset: inout Int) -> (Int, Int)? {
        guard let v = readVarint(bytes, offset: &offset) else { return nil }
        return (v >> 3, v & 7)
    }
    
    private static func readVarint(_ bytes: [UInt8], offset: inout Int) -> Int? {
        var result = 0
        var shift = 0
        while offset < bytes.count {
            let b = bytes[offset]
            offset += 1
            result |= Int(b & 0x7F) << shift
            if (b & 0x80) == 0 { return result }
            shift += 7
            if shift > 35 { return nil }
        }
        return nil
    }
    
    private static func skipField(_ bytes: [UInt8], tag: Int, wireType: Int, offset: inout Int) {
        switch wireType {
        case 0: _ = readVarint(bytes, offset: &offset)
        case 1: offset += 8
        case 2:
            if let len = readVarint(bytes, offset: &offset), offset + len <= bytes.count {
                offset += len
            }
        case 5: offset += 4
        default: break
        }
    }
}

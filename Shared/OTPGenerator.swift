import Foundation
import CryptoKit

nonisolated struct OTPGenerator {

    /// The digit count a code is actually generated with.
    ///
    /// Callers can pass anything: the value arrives from an `otpauth://` URL or a
    /// foreign backup and is not validated at every entry point, and tokens saved
    /// by earlier builds may already hold a bad one. This clamps into a range that
    /// is both meaningful and representable, so generation can never trap.
    ///
    /// The upper bound is 19 rather than the RFC's 8: dynamic truncation yields 31
    /// bits, so anything up to ten digits is genuinely producible, and `10^19` is
    /// the largest power of ten that fits the `UInt64` the modulus is computed in.
    static func effectiveDigits(_ digits: Int) -> Int {
        min(max(digits, 1), 19)
    }

    /// The period a code is actually generated with.
    ///
    /// A non-positive period is malformed input, and dividing by it traps. It
    /// falls back to the RFC default, which is also the value essentially every
    /// issuer uses — so a token whose period was damaged is a 30-second token in
    /// practice, and the user gets a usable code rather than a crash.
    static func effectivePeriod(_ period: Int) -> Int {
        period > 0 ? period : 30
    }

    /// `10^digits` as an integer.
    ///
    /// Deliberately *not* `pow(10, Float(digits))`. That is what this replaced:
    /// `Float` is inexact past 10^10, and `UInt32(...)` traps as soon as the result
    /// passes `UInt32.max`, so a token asking for ten digits crashed the app —
    /// including on every subsequent launch, because the token was already saved.
    private static func modulus(digits: Int) -> UInt64 {
        (0..<digits).reduce(UInt64(1)) { value, _ in value * 10 }
    }

    /// - Parameter now: The moment to generate for. Injectable so the RFC 6238
    ///   reference vectors can be asserted without waiting for the clock, for the
    ///   same reason `SyncMergeEngine.merge` takes `now`. Defaulted, so no caller
    ///   has to know about it.
    static func generateOTP(secret: String, algorithm: OTPAlgorithm = .sha1, digits: Int = 6, period: Int = 30, now: Date = Date()) -> String {
        let safePeriod = effectivePeriod(period)

        // `max(0,)` so a pre-1970 date cannot trap converting a negative value to
        // `UInt64`.
        let counter = UInt64(max(0, now.timeIntervalSince1970) / Double(safePeriod))

        return generate(secret: secret, algorithm: algorithm, digits: digits, counter: counter)
    }

    /// The code for a counter-based token (RFC 4226).
    ///
    /// The only thing that differs from `generateOTP` is where the counter comes
    /// from: the clock there, the token's stored counter here. Everything after
    /// that — the HMAC, the dynamic truncation, the modulus and the padding — is
    /// the same construction *and deliberately the same code*, so the two kinds
    /// cannot drift apart in the parts they have to agree on.
    ///
    /// - Parameter counter: Taken as given. A counter-based code does not expire,
    ///   so a lower counter is the valid code *for that counter* rather than a
    ///   stale one, and there is nothing here that should correct it.
    static func generateHOTP(secret: String, algorithm: OTPAlgorithm = .sha1, digits: Int = 6, counter: UInt64) -> String {
        generate(secret: secret, algorithm: algorithm, digits: digits, counter: counter)
    }

    /// One code, for one counter, however that counter was arrived at.
    private static func generate(secret: String, algorithm: OTPAlgorithm, digits: Int, counter: UInt64) -> String {
        let key = decodeBase32(secret)
        let safeDigits = effectiveDigits(digits)

        // Convert counter to 8-byte big-endian data
        let counterBytes = withUnsafeBytes(of: counter.bigEndian) { Array($0) }

        // Generate HMAC
        let hmac: [UInt8]
        switch algorithm {
        case .sha1:
            let hmacData = HMAC<Insecure.SHA1>.authenticationCode(for: Data(counterBytes), using: SymmetricKey(data: key))
            hmac = Array(hmacData)
        case .sha256:
            let hmacData = HMAC<SHA256>.authenticationCode(for: Data(counterBytes), using: SymmetricKey(data: key))
            hmac = Array(hmacData)
        case .sha512:
            let hmacData = HMAC<SHA512>.authenticationCode(for: Data(counterBytes), using: SymmetricKey(data: key))
            hmac = Array(hmacData)
        }

        // Dynamic truncation
        let offset = Int(hmac.last! & 0x0F)
        let truncatedHash = ((UInt32(hmac[offset]) & 0x7F) << 24) |
                           ((UInt32(hmac[offset + 1]) & 0xFF) << 16) |
                           ((UInt32(hmac[offset + 2]) & 0xFF) << 8) |
                           (UInt32(hmac[offset + 3]) & 0xFF)

        let otpValue = UInt64(truncatedHash) % modulus(digits: safeDigits)

        // Format with leading zeros
        return String(format: "%0\(safeDigits)llu", otpValue)
    }
    
    /// Internal, not private, for `TransferPayload`, which carries a secret as
    /// the bytes it encodes.
    static func decodeBase32(_ string: String) -> Data {
        let base32Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        let string = string.uppercased().replacingOccurrences(of: " ", with: "")
        var bits = 0
        var bitCount = 0
        var result = Data()
        
        for char in string {
            guard let value = base32Alphabet.firstIndex(of: char)?.utf16Offset(in: base32Alphabet) else {
                continue
            }
            
            bits = (bits << 5) | value
            bitCount += 5
            
            if bitCount >= 8 {
                bitCount -= 8
                result.append(UInt8((bits >> bitCount) & 0xFF))
            }
        }
        
        return result
    }
    
    /// Encodes raw secret bytes to Base32 (RFC 4648) for storage. Used when importing Google Authenticator export.
    static func encodeBase32(_ data: Data) -> String {
        let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        var result = ""
        var buffer = 0
        var bitsLeft = 0
        for byte in data {
            buffer = (buffer << 8) | Int(byte)
            bitsLeft += 8
            while bitsLeft >= 5 {
                bitsLeft -= 5
                let index = (buffer >> bitsLeft) & 0x1F
                result.append(alphabet[alphabet.index(alphabet.startIndex, offsetBy: index)])
            }
        }
        if bitsLeft > 0 {
            let index = (buffer << (5 - bitsLeft)) & 0x1F
            result.append(alphabet[alphabet.index(alphabet.startIndex, offsetBy: index)])
        }
        return result
    }
    
    static func isValidSecret(_ secret: String) -> Bool {
        let cleaned = secret.uppercased().replacingOccurrences(of: " ", with: "")
        let base32Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        
        // Check if all characters are valid Base32
        for char in cleaned {
            if !base32Alphabet.contains(char) {
                return false
            }
        }
        
        // Secret should be at least 16 characters for security
        return cleaned.count >= 16
    }
}

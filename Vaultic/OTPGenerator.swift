import Foundation
import CryptoKit

struct OTPGenerator {
    static func generateOTP(secret: String, algorithm: OTPAlgorithm = .sha1, digits: Int = 6, period: Int = 30) -> String {
        let key = decodeBase32(secret)
        let counter = UInt64(Date().timeIntervalSince1970 / Double(period))
        
        // Convert counter to 8-byte big-endian data
        var counterBytes = withUnsafeBytes(of: counter.bigEndian) { Array($0) }
        
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
        
        let otpValue = truncatedHash % UInt32(pow(10, Float(digits)))
        
        // Format with leading zeros
        return String(format: "%0\(digits)d", otpValue)
    }
    
    private static func decodeBase32(_ string: String) -> Data {
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


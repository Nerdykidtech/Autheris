import CryptoKit
import Foundation

/// Password-based encryption for `.autheris` backup files.
///
/// Format: PBKDF2-HMAC-SHA256 (120,000 iterations, 16-byte salt) derives an
/// AES-256-GCM key. The file is a small JSON envelope:
/// `{ "version": 1, "salt": <base64>, "combined": <base64 nonce|ciphertext|tag> }`.
enum BackupCrypto {
    private struct Envelope: Codable {
        let version: Int
        let salt: Data
        let combined: Data
    }

    enum BackupCryptoError: LocalizedError {
        case unsupportedVersion
        case invalidEnvelope

        var errorDescription: String? {
            switch self {
            case .unsupportedVersion:
                return "This backup uses an unsupported format version."
            case .invalidEnvelope:
                return "This file isn't a valid encrypted Autheris backup."
            }
        }
    }

    static func encrypt(plaintext: Data, password: String) throws -> Data {
        let salt = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        let key = deriveKey(password: password, salt: salt)
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else {
            throw BackupCryptoError.invalidEnvelope
        }

        let envelope = Envelope(version: 1, salt: salt, combined: combined)
        return try JSONEncoder().encode(envelope)
    }

    static func decrypt(data: Data, password: String) throws -> Data {
        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            throw BackupCryptoError.invalidEnvelope
        }

        guard envelope.version == 1 else {
            throw BackupCryptoError.unsupportedVersion
        }

        let key = deriveKey(password: password, salt: envelope.salt)
        let sealed = try AES.GCM.SealedBox(combined: envelope.combined)
        return try AES.GCM.open(sealed, using: key)
    }

    // MARK: - Key derivation

    private static func deriveKey(password: String, salt: Data) -> SymmetricKey {
        let keyData = pbkdf2SHA256(password: password, salt: salt, iterations: 120_000)
        return SymmetricKey(data: keyData)
    }

    /// Minimal PBKDF2-HMAC-SHA256 (single 32-byte block, so one output block).
    private static func pbkdf2SHA256(password: String, salt: Data, iterations: Int) -> Data {
        let passwordData = Data(password.utf8)
        var blockIndex = UInt32(1).bigEndian
        var saltBlock = salt
        withUnsafeBytes(of: &blockIndex) { saltBlock.append(contentsOf: $0) }

        var u = Data(HMAC<SHA256>.authenticationCode(
            for: saltBlock,
            using: SymmetricKey(data: passwordData)
        ))
        var result = u

        if iterations > 1 {
            for _ in 1..<iterations {
                u = Data(HMAC<SHA256>.authenticationCode(
                    for: u,
                    using: SymmetricKey(data: passwordData)
                ))
                for index in 0..<result.count {
                    result[index] ^= u[index]
                }
            }
        }

        return result
    }
}

import CommonCrypto
import CryptoKit
import Foundation

/// Password-based encryption for `.autheris` backup files.
///
/// Format: PBKDF2-HMAC-SHA256 with a 16-byte salt derives an AES-256-GCM key.
/// The file is a small JSON envelope:
/// `{ "version": 2, "iterations": 600000, "salt": <base64>, "combined": <base64 nonce|ciphertext|tag> }`.
///
/// Version 1 files have no `iterations` field and always used 120,000. They are
/// still read, but new backups are always written as version 2.
///
/// `nonisolated` so it can run off the main actor: deriving a key takes hundreds
/// of milliseconds by design, and much longer for a file that asks for more
/// rounds. `OTPDataStore` calls it from a detached task.
nonisolated enum BackupCrypto {
    /// The shortest password a new backup accepts. `.autheris` files are made to
    /// be shared, so anyone holding one can guess offline for as long as they like.
    static let minimumPasswordLength = 10

    /// OWASP's current recommendation for PBKDF2-HMAC-SHA256.
    static let currentIterations = 600_000

    private static let legacyIterations = 120_000

    /// What a version 2 file may ask for. The count comes from the file itself,
    /// so it is bounded: too few would let a forged file skip the work, and too
    /// many would hang the app deriving a key.
    private static let acceptedIterations = 100_000...10_000_000

    private struct Envelope: Codable {
        let version: Int
        let iterations: Int?
        let salt: Data
        let combined: Data
    }

    enum BackupCryptoError: LocalizedError {
        case unsupportedVersion
        case invalidEnvelope

        var errorDescription: String? {
            switch self {
            case .unsupportedVersion:
                return String(localized: "This backup uses an unsupported format version.")
            case .invalidEnvelope:
                return String(localized: "This file isn't a valid encrypted Autheris backup.")
            }
        }
    }

    static func encrypt(plaintext: Data, password: String) throws -> Data {
        let salt = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        let key = try deriveKey(password: normalized(password), salt: salt, iterations: currentIterations)
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else {
            throw BackupCryptoError.invalidEnvelope
        }

        let envelope = Envelope(version: 2, iterations: currentIterations, salt: salt, combined: combined)
        return try JSONEncoder().encode(envelope)
    }

    static func decrypt(data: Data, password: String) throws -> Data {
        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            throw BackupCryptoError.invalidEnvelope
        }

        let iterations: Int
        switch envelope.version {
        case 1:
            iterations = legacyIterations
        case 2:
            guard let stored = envelope.iterations, acceptedIterations.contains(stored) else {
                throw BackupCryptoError.invalidEnvelope
            }
            iterations = stored
        default:
            throw BackupCryptoError.unsupportedVersion
        }

        let sealed = try AES.GCM.SealedBox(combined: envelope.combined)

        // The password as typed is tried second, and only when it differs from
        // the normalized one: backups made before passwords were normalized were
        // keyed from the raw bytes, and they still have to open.
        var candidates = [normalized(password)]
        if !password.utf8.elementsEqual(candidates[0].utf8) {
            candidates.append(password)
        }
        var lastError: Error = BackupCryptoError.invalidEnvelope
        for candidate in candidates {
            let key = try deriveKey(password: candidate, salt: envelope.salt, iterations: iterations)
            do {
                return try AES.GCM.open(sealed, using: key)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// The password in one canonical Unicode form (NFC).
    ///
    /// The key is derived from the password's bytes, and one accented letter has
    /// more than one spelling in bytes — "é" composed, or "e" plus a combining
    /// accent — depending on the keyboard and the platform it was typed on. Without
    /// this, a backup made on one device could refuse the right password on
    /// another.
    private static func normalized(_ password: String) -> String {
        password.precomposedStringWithCanonicalMapping
    }

    // MARK: - Key derivation

    private static func deriveKey(password: String, salt: Data, iterations: Int) throws -> SymmetricKey {
        let passwordBytes = Array(password.utf8)
        var derived = [UInt8](repeating: 0, count: 32)
        let status = salt.withUnsafeBytes { saltBytes in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                passwordBytes.map { CChar(bitPattern: $0) }, passwordBytes.count,
                saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                UInt32(iterations),
                &derived, derived.count
            )
        }
        guard status == kCCSuccess else { throw BackupCryptoError.invalidEnvelope }
        return SymmetricKey(data: derived)
    }
}

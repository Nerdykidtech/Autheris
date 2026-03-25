import Foundation

nonisolated enum OTPAlgorithm: String, Codable, CaseIterable, Sendable {
    case sha1 = "SHA1"
    case sha256 = "SHA256"
    case sha512 = "SHA512"
}

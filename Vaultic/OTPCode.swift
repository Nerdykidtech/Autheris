import Foundation

struct OTPCode: Identifiable, Codable {
    let id: UUID
    let label: String
    let account: String
    let secret: String
    let algorithm: OTPAlgorithm
    let digits: Int
    let period: Int
    
    init(id: UUID = UUID(), label: String, account: String, secret: String, algorithm: OTPAlgorithm = .sha1, digits: Int = 6, period: Int = 30) {
        self.id = id
        self.label = label
        self.account = account
        self.secret = secret
        self.algorithm = algorithm
        self.digits = digits
        self.period = period
    }
    
    var currentCode: String {
        OTPGenerator.generateOTP(secret: secret, algorithm: algorithm, digits: digits, period: period)
    }
}


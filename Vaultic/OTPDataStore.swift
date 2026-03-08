import Foundation
import Combine

class OTPDataStore: ObservableObject {
    @Published var codes: [OTPCode] = []
    private let saveKey = "otpCodes"
    
    init() {
        loadCodes()
    }
    
    func saveCodes() {
        if let encoded = try? JSONEncoder().encode(codes) {
            UserDefaults.standard.set(encoded, forKey: saveKey)
        }
    }
    
    func loadCodes() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode([OTPCode].self, from: data) {
            codes = decoded
        } else {
            // Default sample codes with valid Base32 secrets
            codes = [
                OTPCode(label: "GitHub", account: "hunter@dev.com", secret: "JBSWY3DPEHPK3PXP"),
                OTPCode(label: "Google", account: "hunter.eddington", secret: "JBSWY3DPEHPK3PXP"),
                OTPCode(label: "Work VPN", account: "h.eddington", secret: "JBSWY3DPEHPK3PXP")
            ]
            saveCodes()
        }
    }
    
    func addCode(_ code: OTPCode) {
        codes.append(code)
        saveCodes()
    }
    
    func removeCode(at index: Int) {
        codes.remove(at: index)
        saveCodes()
    }
    
    func updateCode(_ code: OTPCode, at index: Int) {
        codes[index] = code
        saveCodes()
    }
}

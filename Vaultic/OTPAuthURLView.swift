import SwiftUI

struct OTPAuthURLView: View {
    let urlString: String
    @ObservedObject var dataStore: OTPDataStore
    @Binding var isPresented: Bool
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 60))
                    .foregroundColor(.accentColor)
                
                Text("Add Authentication Token")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("You've scanned an OTP QR code. Would you like to add this authentication token to your vault?")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                HStack(spacing: 16) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Add Token") {
                        addTokenFromURL()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(40)
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .platformTrailing) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
            .alert("Error", isPresented: $showingAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
            .onAppear {
                #if DEBUG
                print("Processing OTP Auth URL: \(urlString)")
                #endif
            }
        }
    }
    
    private func addTokenFromURL() {
        guard let url = URL(string: urlString), url.scheme == "otpauth" else {
            alertMessage = "Invalid OTP URL"
            showingAlert = true
            return
        }
        
        // Use existing parsing logic from AddTokenView
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var label = ""
        var account = ""
        var secret = ""
        var algorithm: OTPAlgorithm = .sha1
        var digits = 6
        var period = 30
        var secretFound = false
        
        // Handle various path formats
        if path.contains(":") {
            let components = path.components(separatedBy: ":")
            if components.count >= 2 {
                label = components[0]
                account = components[1]
            } else if components.count == 1 {
                label = components[0]
                account = ""
            }
        } else if !path.isEmpty {
            label = path
            account = ""
        }
        
        // Extract parameters from query
        if let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            for item in queryItems {
                switch item.name.lowercased() {
                case "secret":
                    if let value = item.value, !value.isEmpty {
                        secret = value
                        secretFound = true
                    }
                case "algorithm":
                    if let value = item.value?.uppercased() {
                        switch value {
                        case "SHA256", "SHA-256": algorithm = .sha256
                        case "SHA512", "SHA-512": algorithm = .sha512
                        default: algorithm = .sha1
                        }
                    }
                case "digits":
                    if let value = item.value, let digitValue = Int(value) {
                        digits = digitValue
                    }
                case "period":
                    if let value = item.value, let periodValue = Int(value) {
                        period = periodValue
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
        
        // Validate and add
        if !label.isEmpty && secretFound && OTPGenerator.isValidSecret(secret) {
            let newCode = OTPCode(
                label: label,
                account: account,
                secret: secret,
                algorithm: algorithm,
                digits: digits,
                period: period
            )
            dataStore.addCode(newCode)
            isPresented = false
        } else {
            if !secretFound {
                alertMessage = "No secret key found in the URL."
            } else if !OTPGenerator.isValidSecret(secret) {
                alertMessage = "Invalid secret key in the URL."
            } else if label.isEmpty {
                alertMessage = "Service name missing in the URL."
            }
            showingAlert = true
        }
    }
}

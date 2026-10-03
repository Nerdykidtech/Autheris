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
            alertMessage = String(localized: "Invalid OTP URL")
            showingAlert = true
            return
        }
        
        // The parsing lives in `OTPAuthURLParser`, which the scanner and the
        // deep-link path also use. This used to be a third copy of it, and a third
        // copy is a third place for a `hotp` URL to be read as a time-based one.
        guard let parsed = OTPAuthURLParser.parse(url) else {
            alertMessage = String(localized: "Invalid OTP URL")
            showingAlert = true
            return
        }

        guard OTPGenerator.isValidSecret(parsed.secret) else {
            alertMessage = String(localized: "Invalid secret key in the URL.")
            showingAlert = true
            return
        }

        let newCode = OTPCode(
            label: parsed.label,
            account: parsed.account,
            secret: parsed.secret,
            algorithm: parsed.algorithm,
            digits: parsed.digits,
            period: parsed.period,
            kind: parsed.kind,
            counter: parsed.counter
        )
        guard dataStore.addCode(newCode) else {
            alertMessage = String(localized: "A token with this service name and account is already on this device.")
            showingAlert = true
            return
        }
        isPresented = false
    }
}

import SwiftUI
import Foundation
import AVFoundation

struct AddTokenView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var dataStore: OTPDataStore
    
    @State private var selectedTab = 0
    @State private var label = ""
    @State private var account = ""
    @State private var secret = ""
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var isScanning = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab Selector
                Picker("Method", selection: $selectedTab) {
                    Text("Scan QR Code").tag(0)
                    Text("Enter Setup Key").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top)
                
                Divider()
                    .padding(.top, 8)
                
                // Tab content
                if selectedTab == 0 {
                    // QR Code Scanner
                    VStack(spacing: 16) {
                        Spacer()
                        
                        Image(systemName: "qrcode.viewfinder")
                            .font(.system(size: 50))
                            .foregroundColor(.accentColor)
                            .symbolRenderingMode(.hierarchical)
                        
                        Text("Scan QR Code")
                            .font(.title3)
                            .fontWeight(.semibold)
                        
                        Text("Point your camera at a QR code from your authentication app")
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        
                        Spacer()
                        
                        Button(action: {
                            requestCameraPermission()
                        }) {
                            Label("Start Scanning", systemImage: "camera")
                                .font(.headline)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity)
                                .background(
                                    Capsule()
                                        .fill(Color.accentColor)
                                )
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 32)
                        .padding(.bottom, 24)
                    }
                    .frame(maxHeight: .infinity)
                    .padding(.horizontal)
                } else {
                    // Manual Entry Form
                    ScrollView {
                        VStack(spacing: 16) {
                            Spacer()
                                .frame(height: 8)
                            
                            // Form Fields
                            VStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Service Name")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    TextField("e.g., GitHub", text: $label)
                                        .padding(10)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10)
                                                .fill(Color(.secondarySystemBackground))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(Color(.separator), lineWidth: 1)
                                        )
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Account")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    TextField("e.g., user@example.com", text: $account)
                                        .padding(10)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10)
                                                .fill(Color(.secondarySystemBackground))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(Color(.separator), lineWidth: 1)
                                        )
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Setup Key")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    TextField("Enter your setup key", text: $secret)
                                        .autocapitalization(.none)
                                        .disableAutocorrection(true)
                                        .textContentType(.password)
                                        .padding(10)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10)
                                                .fill(Color(.secondarySystemBackground))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(Color(.separator), lineWidth: 1)
                                        )
                                }
                            }
                            .padding(.horizontal, 32)
                            
                            Spacer()
                            
                            Button(action: {
                                validateAndSave()
                            }) {
                                Label("Add Token", systemImage: "plus.circle.fill")
                                    .font(.headline)
                                    .padding(.vertical, 12)
                                    .frame(maxWidth: .infinity)
                                    .background(
                                        Capsule()
                                            .fill(Color.accentColor)
                                    )
                                    .foregroundColor(.white)
                            }
                            .disabled(label.isEmpty || account.isEmpty || secret.isEmpty)
                            .padding(.horizontal, 32)
                            .padding(.bottom, 24)
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
            }
            .navigationTitle("Add Token")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showingAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
            .sheet(isPresented: $isScanning) {
                QRScannerView(isScanning: $isScanning, onCodeScanned: { qrCode in
                    if let qrCode = qrCode {
                        parseQRCode(qrCode)
                    }
                })
                .edgesIgnoringSafeArea(.all)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    
    private func requestCameraPermission() {
        CameraPermissionHelper.checkCameraPermission { granted in
            DispatchQueue.main.async {
                if granted {
                    self.isScanning = true
                } else {
                    self.alertMessage = "Camera access is required to scan QR codes. Please enable it in Settings."
                    self.showingAlert = true
                }
            }
        }
    }
    
    private func parseQRCode(_ qrCode: String) {
        // First, try to parse as otpauth URL (most common)
        if let url = URL(string: qrCode), url.scheme == "otpauth" {
            parseOTPAuthURL(url)
            return
        }
        
        // Try to parse as other OTP formats
        if let otpData = parseOtherOTPFormats(qrCode) {
            label = otpData.label
            account = otpData.account
            secret = otpData.secret
            
            // If we have valid data, auto-switch to manual entry tab
            if !label.isEmpty && !secret.isEmpty && OTPGenerator.isValidSecret(secret) {
                let newCode = OTPCode(
                    label: label,
                    account: account,
                    secret: secret,
                    algorithm: otpData.algorithm,
                    digits: otpData.digits,
                    period: otpData.period
                )
                dataStore.addCode(newCode)
                dismiss()
            } else {
                // Switch to manual entry tab with pre-filled data
                selectedTab = 1
            }
            return
        }
        
        // If it's just a plain Base32 secret
        if OTPGenerator.isValidSecret(qrCode) {
            secret = qrCode
            // Switch to manual entry tab
            selectedTab = 1
            return
        }
        
        // Invalid QR code
        alertMessage = """
        Could not parse QR code. It may not be a valid OTP QR code.
        
        Common formats:
        - otpauth://totp/...
        - otpauth://hotp/...
        - Base32 secret key
        - Other OTP formats
        
        Please enter the details manually.
        """
        showingAlert = true
    }
    
    private func parseOTPAuthURL(_ url: URL) {
        // Extract path components
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        
        // Handle various path formats
        if path.contains(":") {
            // Format: Service:Account
            let components = path.components(separatedBy: ":")
            if components.count >= 2 {
                label = components[0]
                account = components[1]
            } else if components.count == 1 {
                label = components[0]
                account = ""
            }
        } else if !path.isEmpty {
            // Just service name
            label = path
            account = ""
        }
        
        // Default values
        var algorithm: OTPAlgorithm = .sha1
        var digits: Int = 6
        var period: Int = 30
        var secretFound = false
        
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
                        // Handle various algorithm formats
                        switch value {
                        case "SHA1", "SHA-1":
                            algorithm = .sha1
                        case "SHA256", "SHA-256":
                            algorithm = .sha256
                        case "SHA512", "SHA-512":
                            algorithm = .sha512
                        default:
                            algorithm = .sha1
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
                    // Issuer takes precedence over label from path
                    if let issuer = item.value, !issuer.isEmpty {
                        label = issuer
                    }
                case "counter":
                    // For HOTP (counter-based OTP)
                    if let value = item.value, let counterValue = Int(value) {
                        // We'll use this if we add HOTP support
                        print("HOTP counter: \(counterValue)")
                    }
                default:
                    break
                }
            }
        }
        
        // Auto-save if we have enough info
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
            dismiss()
        } else {
            // If secret is invalid or missing, show error
            if !secretFound {
                alertMessage = "No secret key found in QR code. Please enter manually."
                showingAlert = true
            } else if !OTPGenerator.isValidSecret(secret) {
                alertMessage = "Invalid secret key in QR code. Please enter manually."
                showingAlert = true
            } else if label.isEmpty {
                alertMessage = "Service name missing in QR code. Please enter manually."
                showingAlert = true
            } else {
                // Switch to manual entry tab with pre-filled data
                selectedTab = 1
            }
        }
    }
    
    private func parseOtherOTPFormats(_ qrCode: String) -> (label: String, account: String, secret: String, algorithm: OTPAlgorithm, digits: Int, period: Int)? {
        // Try to parse Google Authenticator migration format
        if qrCode.starts(with: "otpauth-migration://") {
            return parseMigrationFormat(qrCode)
        }
        
        // Try to parse as plain parameters string
        // Format: otpauth://totp/Service:Account?secret=ABC&issuer=Service
        if qrCode.contains("secret=") {
            return parseParameterString(qrCode)
        }
        
        return nil
    }
    
    private func parseMigrationFormat(_ qrCode: String) -> (label: String, account: String, secret: String, algorithm: OTPAlgorithm, digits: Int, period: Int)? {
        // Google Authenticator migration format is complex
        // For now, just extract basic info and prompt for manual entry
        if let url = URL(string: qrCode) {
            alertMessage = """
            Google Authenticator migration format detected.
            This format contains multiple tokens and requires special handling.
            
            Please:
            1. Export tokens individually from Google Authenticator
            2. Scan each QR code separately
            3. Or enter the setup key manually
            """
            showingAlert = true
        }
        return nil
    }
    
    private func parseParameterString(_ qrCode: String) -> (label: String, account: String, secret: String, algorithm: OTPAlgorithm, digits: Int, period: Int)? {
        var label = ""
        var account = ""
        var secret = ""
        var algorithm: OTPAlgorithm = .sha1
        var digits = 6
        var period = 30
        
        // Try to extract parameters from a query-like string
        let components = qrCode.components(separatedBy: "&")
        
        for component in components {
            let parts = component.components(separatedBy: "=")
            if parts.count == 2 {
                let key = parts[0].lowercased()
                let value = parts[1]
                
                switch key {
                case "secret":
                    secret = value
                case "issuer", "label":
                    label = value
                case "account":
                    account = value
                case "algorithm":
                    switch value.uppercased() {
                    case "SHA256", "SHA-256":
                        algorithm = .sha256
                    case "SHA512", "SHA-512":
                        algorithm = .sha512
                    default:
                        algorithm = .sha1
                    }
                case "digits":
                    if let digitValue = Int(value) {
                        digits = digitValue
                    }
                case "period":
                    if let periodValue = Int(value) {
                        period = periodValue
                    }
                default:
                    break
                }
            }
        }
        
        return (label, account, secret, algorithm, digits, period)
    }
    
    private func validateAndSave() {
        if !OTPGenerator.isValidSecret(secret) {
            alertMessage = "Please enter a valid Base32 secret key (letters A-Z, numbers 2-7, minimum 16 characters)."
            showingAlert = true
            return
        }
        
        let newCode = OTPCode(
            label: label,
            account: account,
            secret: secret,
            algorithm: .sha1, // Default
            digits: 6, // Default
            period: 30 // Default
        )
        
        dataStore.addCode(newCode)
        dismiss()
    }
}

struct AddTokenView_Previews: PreviewProvider {
    static var previews: some View {
        AddTokenView(dataStore: OTPDataStore())
    }
}


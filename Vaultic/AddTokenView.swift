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
    @State private var showingImportSuccess = false
    @State private var importedTokenCount = 0
    
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
                        
                        Text("Point your camera at a QR code from your authentication app or export file")
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
            .alert("Import Successful", isPresented: $showingImportSuccess) {
                Button("OK", role: .cancel) {
                    dismiss()
                }
            } message: {
                Text("Successfully imported \(importedTokenCount) token\(importedTokenCount == 1 ? "" : "s").")
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
        print("Scanned QR code: \(qrCode)")
        
        // First, check if it's our custom Vaultic URL scheme
        if let url = URL(string: qrCode), url.scheme == "vaultic" {
            print("Detected Vaultic URL scheme")
            if url.host == "import" {
                print("Detected import URL")
                // Extract the data from query parameters
                if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let queryItems = components.queryItems,
                   let dataString = queryItems.first(where: { $0.name == "data" })?.value,
                   let data = decodeVaulticImportData(dataString) {
                    
                    print("Successfully extracted data from URL, size: \(data.count) bytes")
                    
                    // Try to parse as export format
                    if let exportData = parseExportFormatFromData(data) {
                        print("Parsed as export data with \(exportData.tokens.count) tokens")
                        handleExportData(exportData)
                        return
                    } else {
                        print("Failed to parse as export data")
                        alertMessage = "Failed to parse import data. The QR code may be corrupted."
                        showingAlert = true
                        return
                    }
                } else {
                    print("Failed to extract data from URL")
                    alertMessage = "Invalid import URL. Could not extract data."
                    showingAlert = true
                    return
                }
            }
        }
        
        // Then, check if it's an export format (direct Base64 or JSON)
        if let exportData = parseExportFormat(qrCode) {
            print("Detected direct export format with \(exportData.tokens.count) tokens")
            handleExportData(exportData)
            return
        }
        
        // Otherwise, handle as single token...
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
        - Export format (multiple tokens)
        
        Please enter the details manually.
        """
        showingAlert = true
    }

    private func decodeVaulticImportData(_ dataString: String) -> Data? {
        // `vaultic://import?data=...` uses URL-safe Base64 (like RFC 4648 "base64url"):
        // - uses '-' and '_' instead of '+' and '/'
        // - may omit '=' padding
        let standardBase64String = dataString
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let paddingLength = (4 - (standardBase64String.count % 4)) % 4
        let padded = standardBase64String + String(repeating: "=", count: paddingLength)

        return Data(base64Encoded: padded)
    }
    
    private func parseExportFormat(_ qrCode: String) -> ExportData? {
        print("Trying to parse as export format...")
        
        // Try to decode as Base64 first (QR codes often encode binary data as Base64)
        if let data = Data(base64Encoded: qrCode) {
            print("Successfully decoded as Base64, size: \(data.count) bytes")
            return parseExportFormatFromData(data)
        }
        
        // Try as direct JSON string
        if let jsonData = qrCode.data(using: .utf8) {
            print("Trying to parse as JSON string, length: \(qrCode.count) chars")
            return parseExportFormatFromData(jsonData)
        }
        
        print("Not an export format")
        return nil
    }
    
    private func parseExportFormatFromData(_ data: Data) -> ExportData? {
        do {
            let exportData = try JSONDecoder().decode(ExportData.self, from: data)
            print("Successfully parsed ExportData with \(exportData.tokens.count) tokens")
            return exportData
        } catch {
            print("Failed to parse as ExportData: \(error)")
            
            // Try to parse as plain array of OTPCode (old format)
            do {
                let tokens = try JSONDecoder().decode([OTPCode].self, from: data)
                print("Parsed as plain array with \(tokens.count) tokens")
                // Wrap in ExportData for consistency
                return ExportData(version: "1.0", timestamp: Date(), tokens: tokens)
            } catch {
                print("Failed to parse as plain array: \(error)")
                return nil
            }
        }
    }
    
    private func handleExportData(_ exportData: ExportData) {
        print("Handling export data with \(exportData.tokens.count) tokens")
        
        // Filter out duplicates (tokens with same label and account)
        let existingTokens = dataStore.codes
        let newTokens = exportData.tokens.filter { newToken in
            !existingTokens.contains { existingToken in
                existingToken.label == newToken.label && existingToken.account == newToken.account
            }
        }
        
        print("Found \(newTokens.count) new tokens (filtered out \(exportData.tokens.count - newTokens.count) duplicates)")
        
        if newTokens.isEmpty {
            alertMessage = "All \(exportData.tokens.count) token\(exportData.tokens.count == 1 ? "" : "s") in this export already exist on your device."
            showingAlert = true
            return
        }
        
        // Add new tokens
        for token in newTokens {
            print("Adding token: \(token.label) - \(token.account)")
            dataStore.addCode(token)
        }
        
        importedTokenCount = newTokens.count
        showingImportSuccess = true
        
        // Auto-dismiss after successful import
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            dismiss()
        }
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


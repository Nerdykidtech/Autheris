import SwiftUI
import Foundation
import AVFoundation
import PhotosUI
import Vision
import UIKit

struct AddTokenView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var dataStore: OTPDataStore
    @Binding var importResult: (title: String, body: String)?
    
    @State private var selectedTab = 0
    @State private var label = ""
    @State private var account = ""
    @State private var secret = ""
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var isScanning = false
    @State private var showingImagePicker = false
    @State private var isProcessingImage = false
    
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
                        
                        Text("Point your camera at a QR code, or upload a screenshot. Google Authenticator export (otpauth-migration) codes work too.")
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                        
                        Spacer()
                        
                        HStack(spacing: 12) {
                            Button(action: { requestCameraPermission() }) {
                                Label("Scan", systemImage: "camera")
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.vertical, 12)
                                    .frame(maxWidth: .infinity)
                                    .background(Capsule().fill(Color.accentColor))
                                    .foregroundColor(.white)
                            }
                            Button(action: { showingImagePicker = true }) {
                                Label("Upload QR", systemImage: "photo.on.rectangle.angled")
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.vertical, 12)
                                    .frame(maxWidth: .infinity)
                                    .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .padding(.horizontal, 32)
                        
                        Text("Upload a screenshot of a QR code, or a Google Transfer / export image")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 24)
                    }
                    .frame(maxHeight: .infinity)
                    .padding(.horizontal)
                    .overlay {
                        if isProcessingImage {
                            ZStack {
                                Color.black.opacity(0.45)
                                    .ignoresSafeArea()
                                VStack(spacing: 20) {
                                    ProgressView()
                                        .scaleEffect(1.3)
                                        .tint(.white)
                                    Text("Reading QR code…")
                                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.white)
                                }
                                .padding(32)
                                .background(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .fill(.ultraThinMaterial)
                                )
                            }
                        }
                    }
                    .allowsHitTesting(!isProcessingImage)
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
            .overlay(alignment: .center) {
                if showingAlert {
                    ZStack {
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()
                        VStack(spacing: 0) {
                            VStack(spacing: 12) {
                                Text("Something Went Wrong")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .multilineTextAlignment(.center)
                                Text(alertMessage)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                            .padding(.bottom, 16)
                            Divider()
                            Button {
                                showingAlert = false
                            } label: {
                                Text("OK")
                                    .font(.body)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color.accentColor)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(maxWidth: 270)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .zIndex(1)
                    }
                }
            }
            .animation(.easeOut(duration: 0.25), value: showingAlert)
            .sheet(isPresented: $isScanning) {
                QRScannerView(isScanning: $isScanning, onCodeScanned: { qrCode in
                    if let qrCode = qrCode {
                        parseQRCode(qrCode)
                    }
                })
                .edgesIgnoringSafeArea(.all)
            }
            .sheet(isPresented: $showingImagePicker) {
                QRImagePickerView { image in
                    showingImagePicker = false
                    if let image = image {
                        isProcessingImage = true
                        readQRFromImage(image)
                    }
                }
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
    
    private func readQRFromImage(_ image: UIImage) {
        guard let cgImage = image.cgImage else {
            isProcessingImage = false
            deferAlert(message: "Could not read the selected image.")
            return
        }
        // Downscale large photos so Vision runs faster and UI doesn't feel frozen
        let maxDimension: CGFloat = 1024
        let imageToUse: CGImage
        if max(image.size.width, image.size.height) > maxDimension {
            let scale = maxDimension / max(image.size.width, image.size.height)
            let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: newSize)
            let scaled = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
            imageToUse = scaled.cgImage ?? cgImage
        } else {
            imageToUse = cgImage
        }
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        let handler = VNImageRequestHandler(cgImage: imageToUse, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
                let results = request.results ?? []
                let payloads = results.compactMap(\.payloadStringValue)
                if let firstPayload = payloads.first {
                    DispatchQueue.main.async {
                        self.isProcessingImage = false
                        self.parseQRCode(firstPayload)
                    }
                } else {
                    DispatchQueue.main.async {
                        self.isProcessingImage = false
                        self.alertMessage = "No QR code found in this image. Try a clearer screenshot or crop to the QR code."
                        self.showingAlert = true
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isProcessingImage = false
                    self.alertMessage = "Could not process image: \(error.localizedDescription)"
                    self.showingAlert = true
                }
            }
        }
    }
    
    /// Show an alert on the next run loop so it isn't lost when a sheet has just closed.
    private func deferAlert(message: String) {
        DispatchQueue.main.async {
            self.alertMessage = message
            self.showingAlert = true
        }
    }
    
    private func parseQRCode(_ qrCode: String) {
        #if DEBUG
        print("Scanned QR code: \(qrCode)")
        #endif
        
        // First, check if it's our custom Autheris URL scheme
        if let url = URL(string: qrCode), url.scheme == "autheris" {
            #if DEBUG
            print("Detected Autheris URL scheme")
            #endif
            if url.host == "import" {
                #if DEBUG
                print("Detected import URL")
                #endif
                // Extract the data from query parameters
                if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let queryItems = components.queryItems,
                   let dataString = queryItems.first(where: { $0.name == "data" })?.value,
                   let data = decodeAutherisImportData(dataString) {
                    
                    #if DEBUG
                    print("Successfully extracted data from URL, size: \(data.count) bytes")
                    #endif
                    
                    // Try to parse as export format
                    if let exportData = parseExportFormatFromData(data) {
                        #if DEBUG
                        print("Parsed as export data with \(exportData.tokens.count) tokens")
                        #endif
                        handleExportData(exportData)
                        return
                    } else {
                        #if DEBUG
                        print("Failed to parse as export data")
                        #endif
                        alertMessage = "Failed to parse import data. The QR code may be corrupted."
                        showingAlert = true
                        return
                    }
                } else {
                    #if DEBUG
                    print("Failed to extract data from URL")
                    #endif
                    alertMessage = "Invalid import URL. Could not extract data."
                    showingAlert = true
                    return
                }
            }
        }
        
        // Then, check if it's an export format (direct Base64 or JSON)
        if let exportData = parseExportFormat(qrCode) {
            #if DEBUG
            print("Detected direct export format with \(exportData.tokens.count) tokens")
            #endif
            handleExportData(exportData)
            return
        }
        
        // Google Authenticator export (otpauth-migration://offline?data=...)
        if qrCode.hasPrefix("otpauth-migration://"),
           let tokens = GoogleMigrationParser.parseMigrationURL(qrCode), !tokens.isEmpty {
            handleExportData(ExportData(version: "1.0", timestamp: Date(), tokens: tokens))
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

    private func decodeAutherisImportData(_ dataString: String) -> Data? {
        // `autheris://import?data=...` uses URL-safe Base64 (like RFC 4648 "base64url"):
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
        #if DEBUG
        print("Trying to parse as export format...")
        #endif
        
        // Try to decode as Base64 first (QR codes often encode binary data as Base64)
        if let data = Data(base64Encoded: qrCode) {
            #if DEBUG
            print("Successfully decoded as Base64, size: \(data.count) bytes")
            #endif
            return parseExportFormatFromData(data)
        }
        
        // Try as direct JSON string
        if let jsonData = qrCode.data(using: .utf8) {
            #if DEBUG
            print("Trying to parse as JSON string, length: \(qrCode.count) chars")
            #endif
            return parseExportFormatFromData(jsonData)
        }
        
        #if DEBUG
        print("Not an export format")
        #endif
        return nil
    }
    
    private func parseExportFormatFromData(_ data: Data) -> ExportData? {
        do {
            let exportData = try JSONDecoder().decode(ExportData.self, from: data)
            #if DEBUG
            print("Successfully parsed ExportData with \(exportData.tokens.count) tokens")
            #endif
            return exportData
        } catch {
            #if DEBUG
            print("Failed to parse as ExportData: \(error)")
            #endif
            
            // Try to parse as plain array of OTPCode (old format)
            do {
                let tokens = try JSONDecoder().decode([OTPCode].self, from: data)
                #if DEBUG
                print("Parsed as plain array with \(tokens.count) tokens")
                #endif
                // Wrap in ExportData for consistency
                return ExportData(version: "1.0", timestamp: Date(), tokens: tokens)
            } catch {
                #if DEBUG
                print("Failed to parse as plain array: \(error)")
                #endif
                return nil
            }
        }
    }
    
    private func handleExportData(_ exportData: ExportData) {
        #if DEBUG
        print("Handling export data with \(exportData.tokens.count) tokens")
        #endif
        
        // Filter out duplicates (tokens with same label and account)
        let existingTokens = dataStore.codes
        let newTokens = exportData.tokens.filter { newToken in
            !existingTokens.contains { existingToken in
                existingToken.label == newToken.label && existingToken.account == newToken.account
            }
        }
        
        #if DEBUG
        print("Found \(newTokens.count) new tokens (filtered out \(exportData.tokens.count - newTokens.count) duplicates)")
        #endif
        
        if newTokens.isEmpty {
            let count = exportData.tokens.count
            let body = "All \(count) token\(count == 1 ? "" : "s") in this export already exist on your device."
            importResult = ("Already on this device", body)
            dismiss()
            return
        }
        
        // Add new tokens
        for token in newTokens {
            #if DEBUG
            print("Adding token: \(token.label) - \(token.account)")
            #endif
            dataStore.addCode(token)
        }
        
        let count = newTokens.count
        let body = "Successfully imported \(count) token\(count == 1 ? "" : "s")."
        importResult = ("Import Successful", body)
        dismiss()
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
                        #if DEBUG
                        print("HOTP counter: \(counterValue)")
                        #endif
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
        // Google migration is handled above via GoogleMigrationParser. If we land here, parsing failed.
        if qrCode.hasPrefix("otpauth-migration://") {
            alertMessage = "Could not parse this Google Authenticator export. Make sure the QR or image is clear and complete, or try exporting again from Google Authenticator."
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

// MARK: - Image Picker for QR upload (screenshot / Google export)
struct QRImagePickerView: UIViewControllerRepresentable {
    var onImagePicked: (UIImage?) -> Void
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: QRImagePickerView
        
        init(_ parent: QRImagePickerView) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let result = results.first else {
                parent.onImagePicked(nil)
                return
            }
            let parent = self.parent
            result.itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
                DispatchQueue.main.async {
                    parent.onImagePicked(object as? UIImage)
                }
            }
        }
    }
}

struct AddTokenView_Previews: PreviewProvider {
    static var previews: some View {
        AddTokenView(dataStore: OTPDataStore(), importResult: .constant(nil))
    }
}



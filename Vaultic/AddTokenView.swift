import SwiftUI
import Foundation
import AVFoundation
import PhotosUI
// Vision's request types predate Sendable. The request and its handler are
// built here and only ever used on the one background queue that performs them.
@preconcurrency import Vision

struct AddTokenView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var dataStore: OTPDataStore
    @Binding var importResult: (title: String, body: String)?
    /// Where a scanned QR code that carries several codes goes to be reviewed.
    /// Nothing from such a code is added here; see `IncomingLink.scannedBatch`.
    @Environment(\.reviewImport) private var reviewImport
    
    @State private var selectedTab = 0
    @State private var label = ""
    @State private var account = ""
    @State private var secret = ""
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var isScanning = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isProcessingImage = false

    /// Only used by the manual-entry form.
    ///
    /// Manual entry has nothing to read these from — there is no QR or link — so
    /// they start at the otpauth spec's defaults and the user can change them. That
    /// matters for issuers that need something other than SHA-1 and hand you a bare
    /// setup key, which is the case that prompted this (myGov).
    @State private var algorithm: OTPAlgorithm = .sha1
    @State private var digits = 6
    @State private var period = 30

    /// Which kind of code this is, and — for a counter-based one — where its
    /// counter starts.
    ///
    /// Time-based is the default because it is what a bare setup key means to
    /// almost every service; the picker exists for the ones that hand you a
    /// counter instead, which is otherwise impossible to enter by hand. A scanned
    /// QR fills both in from the URL.
    @State private var kind: OTPKind = .totp
    @State private var counter = 0

    /// Account is deliberately optional: plenty of people never fill it in, and the
    /// edit screen has always allowed it to be blank. Requiring it here only meant
    /// the token had to be created and then immediately edited to clear it.
    private var isFormValid: Bool {
        !label.isEmpty && !secret.isEmpty
    }

    /// Typed explicitly: a ternary of two literals infers as `String`, which `Text`
    /// renders verbatim and never looks up — so the string would ship in English in
    /// all seven languages with nothing to notice.
    private var advancedFooter: LocalizedStringKey {
        kind == .totp
            ? "Most services use SHA-1 and 30 seconds. If the service gave you a QR code, scan it instead — the QR carries these settings. Only change the algorithm if your codes are rejected, and your service says which it uses."
            : "Counter-based codes do not expire. The code stays the same until you ask for the next one, which you do from the code's card. Only choose this if your service gave you a starting counter rather than a QR code."
    }
    
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
                            .platformPlainButton()
                            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                Label("Upload QR", systemImage: "photo.on.rectangle.angled")
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.vertical, 12)
                                    .frame(maxWidth: .infinity)
                                    .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                                    .foregroundColor(.accentColor)
                            }
                            .buttonStyle(.plain)
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
                    Form {
                        Section("Token details") {
                            TextField("Service name", text: $label)

                            TextField("Account (optional)", text: $account)
                                .platformTextContentType(.username)
                                .platformNoAutocapitalization()

                            SecureField("Setup key", text: $secret)
                                .platformNoAutocapitalization()
                                .autocorrectionDisabled()
                                .platformTextContentType(.password)
                        }

                        Section {
                            // Which kind of code this is. Named with the acronyms
                            // on purpose: "counter-based" is what the error message
                            // from the service says when a time-based code is
                            // rejected, and HOTP is what its documentation says.
                            Picker("Type", selection: $kind) {
                                Text("Time-based (TOTP)").tag(OTPKind.totp)
                                Text("Counter-based (HOTP)").tag(OTPKind.hotp)
                            }

                            // Defaults to SHA-1, which is what the otpauth spec
                            // assumes when it says nothing. Only worth changing if
                            // the service's setup instructions name another one.
                            Picker("Algorithm", selection: $algorithm) {
                                ForEach(OTPAlgorithm.allCases, id: \.self) { option in
                                    Text(option.rawValue).tag(option)
                                }
                            }

                            Stepper("Digits: \(digits)", value: $digits, in: 6...10)

                            // A time-based code counts down against a period and a
                            // counter-based one against a counter, so exactly one of
                            // these is on screen. Showing the other would be a field
                            // that does nothing.
                            if kind == .totp {
                                Stepper("Period: \(period) seconds", value: $period, in: 15...300, step: 15)
                            } else {
                                Stepper("Counter: \(counter)", value: $counter, in: 0...10_000)
                            }
                        } header: {
                            Text("Advanced")
                        } footer: {
                            Text(advancedFooter)
                        }

                        Section {
                            Button(action: {
                                validateAndSave()
                            }) {
                                Text("Add Token")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                            }
                            .disabled(!isFormValid)
                            .listRowBackground(isFormValid ? Color.accentColor : Color.accentColor.opacity(0.4))
                            .foregroundStyle(.white)
                        } footer: {
                            Text("Enter the same setup key you received when enabling two-factor authentication — or paste the setup link, if that is what the service gave you.")
                        }
                    }
                    .formStyle(.grouped)
                }
            }
            .navigationTitle("Add Token")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .platformSheetLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Something Went Wrong", isPresented: $showingAlert) {
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
                .ignoresSafeArea()
            }
            .onChange(of: selectedPhoto) { _, newItem in
                guard let newItem else { return }
                selectedPhoto = nil
                isProcessingImage = true

                Task {
                    do {
                        if let data = try await newItem.loadTransferable(type: Data.self),
                           let image = PlatformImage(data: data) {
                            await MainActor.run {
                                isProcessingImage = false
                                readQRFromImage(image)
                            }
                        } else {
                            await MainActor.run {
                                isProcessingImage = false
                                alertMessage = String(localized: "Could not read the selected image.")
                                showingAlert = true
                            }
                        }
                    } catch {
                        await MainActor.run {
                            isProcessingImage = false
                            alertMessage = String(localized: "Could not read the selected image: \(error.localizedDescription)")
                            showingAlert = true
                        }
                    }
                }
            }
        }
        .platformSheetDetents(dragIndicator: true)
            .platformSheetSize()
    }
    
    private func requestCameraPermission() {
        CameraPermissionHelper.checkCameraPermission { granted in
            DispatchQueue.main.async {
                if granted {
                    self.isScanning = true
                } else {
                    self.alertMessage = String(localized: "Camera access is required to scan QR codes. Please enable it in Settings.")
                    self.showingAlert = true
                }
            }
        }
    }
    
    private func readQRFromImage(_ image: PlatformImage) {
        guard let cgImage = image.cgImageForExport else {
            isProcessingImage = false
            deferAlert(message: "Could not read the selected image.")
            return
        }
        // Downscale large photos so Vision runs faster and UI doesn't feel frozen
        let maxDimension: CGFloat = 1024
        let imageToUse: CGImage
        let pixelWidth = CGFloat(cgImage.width)
        let pixelHeight = CGFloat(cgImage.height)
        if max(pixelWidth, pixelHeight) > maxDimension {
            let scale = maxDimension / max(pixelWidth, pixelHeight)
            let newSize = CGSize(width: pixelWidth * scale, height: pixelHeight * scale)
            imageToUse = Self.downscaled(cgImage, to: newSize) ?? cgImage
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
                        self.alertMessage = String(localized: "No QR code found in this image. Try a clearer screenshot or crop to the QR code.")
                        self.showingAlert = true
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isProcessingImage = false
                    self.alertMessage = String(localized: "Could not process image: \(error.localizedDescription)")
                    self.showingAlert = true
                }
            }
        }
    }
    
    /// Draws `image` into a smaller bitmap.
    ///
    /// Core Graphics directly rather than a UIKit image renderer, which macOS
    /// does not have — and which is all the renderer was doing underneath anyway.
    private static func downscaled(_ image: CGImage, to size: CGSize) -> CGImage? {
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        guard width > 0, height > 0,
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// Show an alert on the next run loop so it isn't lost when a sheet has just closed.
    private func deferAlert(message: String) {
        DispatchQueue.main.async {
            self.alertMessage = message
            self.showingAlert = true
        }
    }
    
    private func parseQRCode(_ qrCode: String) {
        // Deliberately not logging `qrCode`: it is usually an otpauth:// URI that
        // embeds the TOTP secret, and a secret must never reach the system log.
        #if DEBUG
        print("Scanned QR payload: \(qrCode.count) chars")
        #endif
        
        // A QR code carrying several codes: a transfer, a Google Authenticator
        // export, or an older bare export. Reviewed before anything is added.
        switch IncomingLink.scannedBatch(qrCode) {
        case .tokens(let tokens):
            reviewImport(tokens)
            dismiss()
            return
        case .failure(_, let message):
            alertMessage = message
            showingAlert = true
            return
        case nil:
            break
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
                addAndDismiss(newCode)
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
        alertMessage = String(localized: """
        Could not parse QR code. It may not be a valid OTP QR code.
        
        Common formats:
        - otpauth://totp/...
        - otpauth://hotp/...
        - Base32 secret key
        - Export format (multiple tokens)
        
        Please enter the details manually.
        """)
        showingAlert = true
    }

    /// Adds one code and closes, or says it is already here rather than closing as
    /// if it had been added.
    private func addAndDismiss(_ code: OTPCode) {
        if !dataStore.addCode(code) {
            importResult = (String(localized: "Already on this device"),
                            String(localized: "A token with this service name and account is already on this device."))
        }
        dismiss()
    }
    
    /// A scanned setup URL (`otpauth://totp/...` or `otpauth://hotp/...`).
    ///
    /// The parsing lives in `OTPAuthURLParser`, which the deep-link path
    /// (`IncomingLink`) also uses.
    /// Three copies of it used to exist here and there, and they had already
    /// drifted: this one was the only one that even noticed a `counter`, it only
    /// printed it, and none of the three read the URL's host — so a counter-based
    /// code was saved as a time-based one and silently never worked.
    private func parseOTPAuthURL(_ url: URL) {
        guard let parsed = OTPAuthURLParser.parse(url) else {
            // Either the label or the secret is missing, and no fallback can invent
            // one. The manual form is what is left, and it is where this has always
            // sent people.
            selectedTab = 1
            alertMessage = String(localized: "No secret key found in QR code. Please enter manually.")
            showingAlert = true
            return
        }

        guard OTPGenerator.isValidSecret(parsed.secret) else {
            // Prefilled rather than thrown away: the key is there, it is only not
            // Base32, and correcting it by hand beats scanning the code again.
            prefill(from: parsed)
            selectedTab = 1
            alertMessage = String(localized: "Invalid secret key in QR code. Please enter manually.")
            showingAlert = true
            return
        }

        // Auto-save if we have enough info
        addAndDismiss(OTPCode(
            label: parsed.label,
            account: parsed.account,
            secret: parsed.secret,
            algorithm: parsed.algorithm,
            digits: parsed.digits,
            period: parsed.period,
            kind: parsed.kind,
            counter: parsed.counter
        ))
    }

    /// Fills the manual form from a parsed URL, so a setup code that cannot be saved
    /// outright still arrives on screen in one piece instead of being retyped.
    private func prefill(from parsed: ParsedOTPAuth) {
        label = parsed.label
        account = parsed.account
        secret = parsed.secret
        algorithm = parsed.algorithm
        // Clamped into the ranges the steppers offer, so a URL carrying a value
        // outside them opens as a usable one rather than leaving a control blank.
        digits = min(max(parsed.digits, 6), 10)
        period = min(max(parsed.period, 15), 300)
        kind = parsed.kind
        counter = Int(min(parsed.counter, UInt64(Int.max)))
    }
    
    private func parseOtherOTPFormats(_ qrCode: String) -> (label: String, account: String, secret: String, algorithm: OTPAlgorithm, digits: Int, period: Int)? {
        // Try to parse Google Authenticator migration format
        if qrCode.starts(with: "otpauth-migration://") {
            return parseMigrationFormat(qrCode)
        }

        // Try to parse as a bare parameters string.
        //
        // Whatever reaches this point is *not* a well-formed `otpauth://` URL —
        // everything with an `otpauth` scheme went to `OTPAuthURLParser` above — so
        // there is no host here to say which kind of code it is and the result is
        // time-based. That is what this has always produced, and it is the right
        // answer for the inputs it sees: a `secret=…&issuer=…` string with no host at
        // all.
        if qrCode.contains("secret=") {
            return parseParameterString(qrCode)
        }
        
        return nil
    }
    
    private func parseMigrationFormat(_ qrCode: String) -> (label: String, account: String, secret: String, algorithm: OTPAlgorithm, digits: Int, period: Int)? {
        // Google migration is handled above via GoogleMigrationParser. If we land here, parsing failed.
        if qrCode.hasPrefix("otpauth-migration://") {
            alertMessage = String(localized: "Could not parse this Google Authenticator export. Make sure the QR or image is clear and complete, or try exporting again from Google Authenticator.")
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
        // A pasted setup *link* rather than a bare key. Plenty of services hand you
        // one on their website — and on a Mac, or for anyone who was sent the link
        // in a message, that is the only thing there is to copy. The field used to
        // reject it outright, because a URL is not Base32: "please enter a valid
        // Base32 secret key", with the link still sitting in the box.
        //
        // Parsed exactly as a scanned QR code is, so the link's own kind, algorithm
        // and counter win over the defaults on screen — and a counter-based link
        // arrives as a counter-based code, which is the case that was silently wrong
        // before this release.
        if let parsed = OTPAuthURLParser.parseLink(secret),
           OTPGenerator.isValidSecret(parsed.secret) {
            addAndDismiss(OTPCode(
                label: parsed.label,
                account: parsed.account,
                secret: parsed.secret,
                algorithm: parsed.algorithm,
                digits: parsed.digits,
                period: parsed.period,
                kind: parsed.kind,
                counter: parsed.counter
            ))
            return
        }

        // Not a link, or a link whose secret is unusable: the ordinary Base32 path,
        // including its message about what a valid key looks like.
        if !OTPGenerator.isValidSecret(secret) {
            alertMessage = String(localized: "Please enter a valid Base32 secret key (letters A-Z, numbers 2-7, minimum 16 characters).")
            showingAlert = true
            return
        }
        
        let newCode = OTPCode(
            label: label,
            account: account,
            secret: secret,
            algorithm: algorithm,
            digits: digits,
            period: period,
            kind: kind,
            counter: UInt64(max(0, counter))
        )
        
        addAndDismiss(newCode)
    }
}

struct AddTokenView_Previews: PreviewProvider {
    static var previews: some View {
        AddTokenView(dataStore: OTPDataStore(), importResult: .constant(nil))
            .environment(\.reviewImport, ReviewImportAction { _ in })
    }
}

import SwiftUI
import Foundation
import AVFoundation
import Combine

struct HomeView: View {
    @StateObject private var dataStore = OTPDataStore()
    @State private var showingAddToken = false
    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(dataStore.codes) { code in
                        OTPCardView(code: code, dataStore: dataStore)
                    }
                    
                    // Empty state when no tokens
                    if dataStore.codes.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "lock.shield")
                                .font(.system(size: 40))
                                .foregroundColor(.accentColor)
                                .opacity(0.5)
                            
                            Text("No Tokens Yet")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            Text("Add your first authentication token to get started")
                                .font(.subheadline)
                                .foregroundColor(.secondary.opacity(0.8))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                        .padding(.vertical, 50)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
            .navigationTitle("Vaultic")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                // Swapped positions: ellipsis on left, plus on right
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        // Settings or edit action
                    }) {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    // Add token button on the right (standard iOS pattern)
                    Button(action: {
                        showingAddToken = true
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundColor(.accentColor)
                    }
                }
            }
            .sheet(isPresented: $showingAddToken) {
                AddTokenView(dataStore: dataStore)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .onReceive(timer) { _ in
                // Force view update every second for countdown
            }
        }
    }
}

struct OTPCardView: View {
    let code: OTPCode
    let dataStore: OTPDataStore
    
    @State private var remainingSeconds: Int = 30
    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var isCopied = false
    @State private var showDeleteConfirmation = false
    @State private var showEditSheet = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with service info and timer
            HStack(alignment: .center, spacing: 8) {
                // Service icon/placeholder
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.08))
                        .frame(width: 28, height: 28)
                    
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(code.label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(remainingSeconds <= 5 ? .red : .primary)
                        .lineLimit(1)
                    
                    if !code.account.isEmpty {
                        Text(code.account)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // Compact timer
                ZStack {
                    // Progress circle background
                    Circle()
                        .stroke(lineWidth: 1.8)
                        .foregroundColor(Color.gray.opacity(0.1))
                        .frame(width: 28, height: 28)
                    
                    // Progress circle
                    Circle()
                        .trim(from: 0, to: CGFloat(remainingSeconds) / 30)
                        .stroke(
                            style: StrokeStyle(
                                lineWidth: 1.8,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                        .foregroundColor(remainingSeconds <= 5 ? .red : .accentColor)
                        .rotationEffect(.degrees(-90))
                        .frame(width: 28, height: 28)
                    
                    // Timer text
                    Text("\(remainingSeconds)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(remainingSeconds <= 5 ? .red : .secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)
            
            // OTP Code area - More modern and compact
            ZStack {
                // Modern rounded background
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.tertiarySystemBackground))
                    .padding(.horizontal, 12)
                    .frame(height: 42) // More compact height
                
                if isCopied {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.accentColor)
                        
                        Text("Copied")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.accentColor)
                    }
                } else {
                    Text(code.currentCode)
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundColor(remainingSeconds <= 5 ? .red : .primary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(.vertical, 10)
        }
        .background(
            ZStack {
                // Card background with subtle professional look
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground))
                    .shadow(
                        color: Color.black.opacity(0.05),
                        radius: 6,
                        x: 0,
                        y: 2
                    )
                
                // Clean subtle border
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(.separator).opacity(0.12), lineWidth: 0.5)
                
                // Red overlay effect when 5 seconds or less
                if remainingSeconds <= 5 {
                    RoundedRectangle(cornerRadius: 16)
                        .inset(by: -1)
                        .fill(
                            LinearGradient(
                                colors: [.red.opacity(0.05), .red.opacity(0.01)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: [.red.opacity(0.25), .red.opacity(0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                        .shadow(color: .red.opacity(0.12), radius: 4, x: 0, y: 0)
                }
            }
        )
        .overlay(
            Group {
                if remainingSeconds <= 5 {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: [.red.opacity(0.2), .red.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.6
                        )
                }
            }
        )
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
        .onTapGesture {
            // Tap to copy
            copyToClipboard()
        }
        .onLongPressGesture {
            // Long press for context menu/action sheet
            showActionSheet()
        }
        .confirmationDialog("Manage Token", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Edit", role: .none) {
                showEditSheet = true
            }
            
            Button("Delete", role: .destructive) {
                deleteToken()
            }
            
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Choose an action for \(code.label)")
        }
        .sheet(isPresented: $showEditSheet) {
            EditTokenView(code: code, dataStore: dataStore)
        }
        .onAppear {
            updateRemainingSeconds()
        }
        .onReceive(timer) { _ in
            updateRemainingSeconds()
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: remainingSeconds <= 5)
        .animation(.easeInOut(duration: 0.2), value: isCopied)
    }
    
    private func updateRemainingSeconds() {
        let currentTime = Date().timeIntervalSince1970
        let period = Double(code.period)
        let elapsed = currentTime.truncatingRemainder(dividingBy: period)
        let newRemainingSeconds = Int(period - elapsed)
        
        if newRemainingSeconds != remainingSeconds {
            remainingSeconds = newRemainingSeconds
        }
    }
    
    private func copyToClipboard() {
        UIPasteboard.general.string = code.currentCode
        withAnimation {
            isCopied = true
        }
        
        // Reset after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                isCopied = false
            }
        }
    }
    
    private func showActionSheet() {
        showDeleteConfirmation = true
    }
    
    private func deleteToken() {
        if let index = dataStore.codes.firstIndex(where: { $0.id == code.id }) {
            dataStore.removeCode(at: index)
        }
    }
}

// MARK: - Edit Token View
struct EditTokenView: View {
    let code: OTPCode
    @ObservedObject var dataStore: OTPDataStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var label: String
    @State private var account: String
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    init(code: OTPCode, dataStore: OTPDataStore) {
        self.code = code
        self.dataStore = dataStore
        _label = State(initialValue: code.label)
        _account = State(initialValue: code.account)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()
                
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Service Name")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        TextField("e.g., GitHub", text: $label)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.secondarySystemBackground))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color(.separator), lineWidth: 1)
                            )
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Account")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        TextField("e.g., user@example.com", text: $account)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.secondarySystemBackground))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color(.separator), lineWidth: 1)
                            )
                    }
                }
                .padding(.horizontal, 40)
                
                Spacer()
                
                Button(action: {
                    saveChanges()
                }) {
                    Label("Save Changes", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(
                            Capsule()
                                .fill(Color.accentColor)
                        )
                        .foregroundColor(.white)
                }
                .disabled(label.isEmpty)
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
            .navigationTitle("Edit Token")
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
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
    
    private func saveChanges() {
        if label.isEmpty {
            alertMessage = "Service name cannot be empty."
            showingAlert = true
            return
        }
        
        let updatedCode = OTPCode(
            id: code.id,
            label: label,
            account: account,
            secret: code.secret,
            algorithm: code.algorithm,
            digits: code.digits,
            period: code.period
        )
        
        if let index = dataStore.codes.firstIndex(where: { $0.id == code.id }) {
            dataStore.updateCode(updatedCode, at: index)
        }
        
        dismiss()
    }
}

// MARK: - Add Token View with Tabs
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
    @State private var scannedQRCode: String?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab Selector - Keep on top
                Picker("Method", selection: $selectedTab) {
                    Text("Scan QR Code").tag(0)
                    Text("Enter Setup Key").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()
                
                Divider()
                
                // Tab content with consistent height
                if selectedTab == 0 {
                    // QR Code Scanner - Compact version
                    VStack(spacing: 16) { // Reduced spacing
                        Spacer()
                        
                        Image(systemName: "qrcode.viewfinder")
                            .font(.system(size: 60)) // Smaller icon
                            .foregroundColor(.accentColor)
                            .symbolRenderingMode(.hierarchical)
                        
                        Text("Scan QR Code")
                            .font(.title3) // Smaller font
                            .fontWeight(.semibold)
                            .padding(.top, 4)
                        
                        Text("Point your camera at a QR code from your authentication app")
                            .font(.callout) // Smaller font
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32) // Reduced padding
                        
                        Spacer()
                        
                        Button(action: {
                            requestCameraPermission()
                        }) {
                            Label("Start Scanning", systemImage: "camera")
                                .font(.headline)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity)
                                .background(
                                    Capsule()
                                        .fill(Color.accentColor)
                                )
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 32) // Reduced padding
                        .padding(.bottom, 24) // Reduced padding
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    // Manual Entry Form - Compact layout
                    VStack(spacing: 16) { // Reduced spacing
                        Spacer()
                        
                        // Form Fields only - more compact
                        VStack(spacing: 12) { // Reduced spacing
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Service Name")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                TextField("e.g., GitHub", text: $label)
                                    .padding(10) // Reduced padding
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
                        .padding(.horizontal, 32) // Reduced padding
                        
                        Spacer()
                        
                        // Add Button - smaller
                        Button(action: {
                            validateAndSave()
                        }) {
                            Label("Add", systemImage: "plus.circle.fill")
                                .font(.headline)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
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
            .alert("Invalid Secret", isPresented: $showingAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
        }
    }
    
    private func requestCameraPermission() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                if granted {
                    isScanning = true
                } else {
                    alertMessage = "Camera access is required to scan QR codes. Please enable it in Settings."
                    showingAlert = true
                }
            }
        }
    }
    
    private func parseQRCode(_ qrCode: String) {
        // Parse otpauth:// URLs
        if let url = URL(string: qrCode),
           url.scheme == "otpauth",
           url.host == "totp" {
            
            let path = url.path
            let components = path.components(separatedBy: ":")
            
            if components.count >= 2 {
                label = components[0].trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                account = components[1]
            } else if components.count == 1 {
                label = components[0].trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                account = ""
            }
            
            // Extract parameters from query
            if let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
                for item in queryItems {
                    if item.name == "secret", let value = item.value {
                        secret = value
                    }
                }
            }
            
            // Auto-save if we have enough info
            if !label.isEmpty && !secret.isEmpty {
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
        } else {
            alertMessage = "Invalid QR code. Please scan a valid OTP QR code."
            showingAlert = true
        }
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

// MARK: - QRScannerView placeholder
struct QRScannerView: View {
    let onCodeScanned: (String?) -> Void
    
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            
            VStack {
                Text("QR Scanner Placeholder")
                    .foregroundColor(.white)
                    .font(.title)
                
                Text("Camera permission required")
                    .foregroundColor(.gray)
                    .padding()
                
                Button("Cancel") {
                    onCodeScanned(nil)
                }
                .padding()
                .background(Color.white)
                .foregroundColor(.black)
                .cornerRadius(10)
            }
        }
        .onAppear {
            // This is a placeholder - implement actual QR scanning here
            print("QR Scanner placeholder appeared")
        }
    }
}

// MARK: - Preview
#Preview {
    HomeView()
}


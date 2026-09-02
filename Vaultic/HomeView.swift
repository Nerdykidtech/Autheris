import SwiftUI
import Foundation
import AVFoundation
import Combine
import MessageUI
import UIKit

struct HomeView: View {
    @EnvironmentObject private var dataStore: OTPDataStore
    @State private var showingAddToken = false
    @State private var importResult: (title: String, body: String)? = nil
    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var searchText = ""
    @State private var showingBackupView = false
    @State private var showingQRCodeView = false
    @State private var showingSupportMail = false
    @State private var showingSettings = false
    @State private var showingChangelog = false
    @State private var supportTo = "autheris@eddington.tech"
    @State private var supportSubject = "Support Request from Autheris User"
    @State private var supportBody = SupportMailData.troubleshootingTemplate()
    @State private var showingSupportError = false
    @State private var supportErrorMessage = ""
    
    var filteredCodes: [OTPCode] {
        if searchText.isEmpty {
            return dataStore.codes
        } else {
            return dataStore.codes.filter { code in
                code.label.localizedCaseInsensitiveContains(searchText) ||
                code.account.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    // Search bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                            .font(.system(size: 17))
                        
                        TextField("Search tokens", text: $searchText)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(.system(size: 17))
                            .foregroundColor(.primary)
                        
                        if !searchText.isEmpty {
                            Button(action: {
                                searchText = ""
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 17))
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                    
                    ForEach(filteredCodes) { code in
                        OTPCardView(code: code, dataStore: dataStore)
                    }
                    
                    // Empty state when no tokens or no search results
                    if filteredCodes.isEmpty {
                        VStack(spacing: 12) {
                            if searchText.isEmpty {
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
                            } else {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 40))
                                    .foregroundColor(.secondary)
                                    .opacity(0.5)
                                
                                Text("No Results")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                
                                Text("No tokens match \"\(searchText)\"")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary.opacity(0.8))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 40)
                            }
                        }
                        .padding(.vertical, 50)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
            .navigationTitle("Autheris")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                // Swapped positions: ellipsis on left, plus on right
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Button(action: {
                            showingBackupView = true
                        }) {
                            Label("Backup", systemImage: "externaldrive.badge.plus")
                        }
                        
                        Button(action: {
                            showingQRCodeView = true
                        }) {
                            Label("Transfer via QR Code", systemImage: "qrcode")
                        }
                        
                        // Add Settings option to the menu
                        Button(action: {
                            showingSettings = true
                        }) {
                            Label("Settings", systemImage: "gear")
                        }
                        
                        Button(action: {
                            showingChangelog = true
                        }) {
                            Label("Changelog", systemImage: "list.bullet.rectangle")
                        }
                        
                        Divider()
                        
                        Button(action: {
                            presentSupportEmail()
                        }) {
                            Label("Support", systemImage: "envelope")
                        }
                    } label: {
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
                AddTokenView(dataStore: dataStore, importResult: $importResult)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingBackupView) {
                BackupView(dataStore: dataStore)
            }
            .sheet(isPresented: $showingQRCodeView) {
                if let exportData = dataStore.exportData() {
                    QRCodeView(data: exportData, title: "Export Tokens")
                } else {
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 50))
                            .foregroundColor(.orange)
                        
                        Text("Unable to Generate QR Code")
                            .font(.headline)
                        
                        Text("There was an error preparing your tokens for export.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        Button("Dismiss") {
                            showingQRCodeView = false
                        }
                        .padding(.top, 20)
                    }
                    .padding()
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingChangelog) {
                ChangelogView()
            }
            .sheet(isPresented: $showingSupportMail) {
                SupportMailComposer(
                    to: supportTo,
                    subject: supportSubject,
                    body: supportBody
                )
            }
            .overlay {
                if showingSupportError {
                    ZStack {
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()
                        VStack(spacing: 0) {
                            VStack(spacing: 12) {
                                Text("Support Email")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .multilineTextAlignment(.center)
                                Text(supportErrorMessage)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                            .padding(.bottom, 16)
                            Divider()
                            Button {
                                showingSupportError = false
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
            .animation(.easeOut(duration: 0.25), value: showingSupportError)
            .overlay {
                if let result = importResult {
                    ZStack {
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()
                        VStack(spacing: 0) {
                            VStack(spacing: 12) {
                                Text(result.title)
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .multilineTextAlignment(.center)
                                Text(result.body)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                            .padding(.bottom, 16)
                            Divider()
                            Button {
                                importResult = nil
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
            .animation(.easeOut(duration: 0.25), value: importResult != nil)
            .onReceive(timer) { _ in
                // Force view update every second for countdown
            }
        }
    }

    private func presentSupportEmail() {
        supportTo = "autheris@eddington.tech"
        supportSubject = "Support Request from Autheris User"
        supportBody = SupportMailData.troubleshootingTemplate()

        if MFMailComposeViewController.canSendMail() {
            showingSupportMail = true
            return
        }

        // Fallback: open Mail app via mailto:
        guard let url = SupportMailData.mailtoURL(to: supportTo, subject: supportSubject, body: supportBody) else {
            supportErrorMessage = "Unable to open Mail. Please email \(supportTo) with subject \"\(supportSubject)\"."
            showingSupportError = true
            return
        }

        UIApplication.shared.open(url)
    }
}

private struct SupportMailData {
    let to: String
    let subject: String
    let body: String

    static func troubleshootingTemplate() -> String {
        let device = UIDevice.current

        let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "Unknown"
        let build = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "Unknown"

        let modelIdentifier = Self.modelIdentifier() ?? "Unknown"

        return """
        Hi Autheris Support,

        I need help with:
        - Issue summary:
        - What I expected to happen:
        - What actually happened:
        - Steps to reproduce:

        Error message (if any):
        -

        Troubleshooting tried:
        -

        Device info:
        - Device: \(device.model) (\(modelIdentifier))
        - iOS: \(device.systemVersion)
        - Autheris: \(appVersion) (\(build))

        Thanks!
        """
    }

    static func mailtoURL(to: String, subject: String, body: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = to
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        return components.url
    }

    static func modelIdentifier() -> String? {
        var systemInfo = utsname()
        uname(&systemInfo)

        let mirror = Mirror(reflecting: systemInfo.machine)
        return mirror.children.compactMap { element -> String? in
            guard let value = element.value as? Int8, value != 0 else { return nil }
            return String(UnicodeScalar(UInt8(value)))
        }.joined()
    }
}

private struct SupportMailComposer: UIViewControllerRepresentable {
    let to: String
    let subject: String
    let body: String

    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: { dismiss() })
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients([to])
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        private let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            onFinish()
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
    @State private var showSecretSheet = false
    
    // Haptic feedback generators
    private let copyHaptic = UIImpactFeedbackGenerator(style: .light)
    private let longPressHaptic = UIImpactFeedbackGenerator(style: .medium)
    private let deleteHaptic = UINotificationFeedbackGenerator()
    
    // Compute warning threshold based on period
    private var warningThreshold: Int {
        return max(5, Int(Double(code.period) * 0.1667)) // 5 seconds or 1/6 of period
    }

    private var branding: IssuerBranding {
        IssuerBranding.forLabel(code.label)
    }
    
    private var timerRingColor: Color {
        if let hex = code.timerRingHex, let c = Color(hex: hex) {
            return c
        }
        return branding.color
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with service info and timer
            HStack(alignment: .center, spacing: 8) {
                IssuerIconView(branding: branding)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(code.label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(remainingSeconds <= warningThreshold ? .red : .primary)
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
                    
                    // Progress circle - NOW DYNAMIC BASED ON PERIOD
                    Circle()
                        .trim(from: 0, to: CGFloat(remainingSeconds) / CGFloat(code.period))
                        .stroke(
                            style: StrokeStyle(
                                lineWidth: 1.8,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                        .foregroundColor(remainingSeconds <= warningThreshold ? .red : timerRingColor)
                        .rotationEffect(.degrees(-90))
                        .frame(width: 28, height: 28)
                    
                    // Timer text
                    Text("\(remainingSeconds)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(remainingSeconds <= warningThreshold ? .red : .secondary)
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
                        .foregroundColor(remainingSeconds <= warningThreshold ? .red : .primary)
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
                
                // Red overlay effect when near expiration
                if remainingSeconds <= warningThreshold {
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
                if remainingSeconds <= warningThreshold {
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
            // Tap to copy with haptic feedback
            copyToClipboard()
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            // Long press for context menu/action sheet with haptic feedback
            longPressHaptic.impactOccurred()
            showActionSheet()
        }
        .confirmationDialog("Manage Token", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("View Secret", role: .none) {
                showSecretSheet = true
            }
            
            Button("Edit", role: .none) {
                showEditSheet = true
            }
            
            Button("Delete", role: .destructive) {
                // Haptic feedback for delete action
                deleteHaptic.notificationOccurred(.warning)
                deleteToken()
            }
            
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Choose an action for \(code.label)")
        }
        .sheet(isPresented: $showEditSheet) {
            EditTokenView(code: code, dataStore: dataStore)
        }
        .sheet(isPresented: $showSecretSheet) {
            TokenSecretView(code: code, dataStore: dataStore)
        }
        .onAppear {
            updateRemainingSeconds()
        }
        .onReceive(timer) { _ in
            updateRemainingSeconds()
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: remainingSeconds <= warningThreshold)
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
        // Light haptic feedback for copy
        copyHaptic.impactOccurred()
        
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

struct EditTokenView: View {
    let code: OTPCode
    @ObservedObject var dataStore: OTPDataStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var label: String
    @State private var account: String
    @State private var ringColor: Color
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var showDiscardConfirmation = false
    
    // Haptic feedback for save
    private let saveHaptic = UINotificationFeedbackGenerator()
    
    private var editBranding: IssuerBranding {
        IssuerBranding.forLabel(code.label)
    }
    
    private var isDirty: Bool {
        label != code.label ||
        account != code.account ||
        ringHexForSave() != code.timerRingHex
    }
    
    init(code: OTPCode, dataStore: OTPDataStore) {
        self.code = code
        self.dataStore = dataStore
        _label = State(initialValue: code.label)
        _account = State(initialValue: code.account)
        let branding = IssuerBranding.forLabel(code.label)
        if let hex = code.timerRingHex, let c = Color(hex: hex) {
            _ringColor = State(initialValue: c)
        } else {
            _ringColor = State(initialValue: branding.color)
        }
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
                    
                    VStack(alignment: .leading, spacing: 8) {
                            Text("Countdown ring")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        VStack(alignment: .leading, spacing: 10) {
                            ColorPicker(selection: $ringColor, supportsOpacity: false) {
                                HStack(spacing: 14) {
                                    ZStack {
                                        Circle()
                                            .stroke(Color(.separator).opacity(0.35), lineWidth: 1)
                                            .frame(width: 44, height: 44)
                                        Circle()
                                            .stroke(ringColor, lineWidth: 3.5)
                                            .frame(width: 36, height: 36)
                                    }
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("Ring color")
                                            .font(.body.weight(.medium))
                                            .foregroundStyle(.primary)
                                        Text(ringColorMatchesBranding ? "Automatic (service color)" : "Custom color")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 8)
                                }
                                .contentShape(Rectangle())
                            }
                            
                            HStack {
                                Spacer(minLength: 0)
                                Button("Use service default") {
                                    ringColor = editBranding.color
                                }
                                .font(.footnote.weight(.semibold))
                                .buttonStyle(.bordered)
                            }
                        }
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
                                .fill(isDirty ? Color.accentColor : Color.accentColor.opacity(0.4))
                        )
                        .foregroundColor(.white)
                }
                .disabled(!isDirty)
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
            .navigationTitle("Edit Token")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        if isDirty {
                            showDiscardConfirmation = true
                        } else {
                            dismiss()
                        }
                    }
                }
            }
            .interactiveDismissDisabled(isDirty)
            .confirmationDialog(
                "Unsaved Changes",
                isPresented: $showDiscardConfirmation,
                titleVisibility: .visible
            ) {
                Button("Discard Changes", role: .destructive) {
                    dismiss()
                }
                Button("Keep Editing", role: .cancel) { }
            } message: {
                Text("Your edits have not been saved.")
            }
            .alert("Error", isPresented: $showingAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    
    private var ringColorMatchesBranding: Bool {
        guard let picked = ringColor.rgbHexStringForStorage(),
              let brand = editBranding.color.rgbHexStringForStorage() else {
            return false
        }
        return picked == brand
    }
    
    /// `nil` when the chosen color matches the automatic service color (same as legacy “default”).
    private func ringHexForSave() -> String? {
        guard let picked = ringColor.rgbHexStringForStorage() else { return code.timerRingHex }
        guard let brand = editBranding.color.rgbHexStringForStorage() else { return picked }
        return picked == brand ? nil : picked
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
            period: code.period,
            timerRingHex: ringHexForSave()
        )
        
        if let index = dataStore.codes.firstIndex(where: { $0.id == code.id }) {
            dataStore.updateCode(updatedCode, at: index)
            // Success haptic feedback
            saveHaptic.notificationOccurred(.success)
        }
        
        dismiss()
    }
}

#Preview {
    HomeView()
        .environmentObject(OTPDataStore())
}


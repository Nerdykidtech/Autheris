import SwiftUI
import Foundation
import Combine
import UIKit

struct HomeView: View {
    @EnvironmentObject private var dataStore: OTPDataStore
    @State private var showingAddToken = false
    @State private var importResult: (title: String, body: String)? = nil
    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var searchText = ""
    @State private var showingSettings = false
    
    var filteredCodes: [OTPCode] {
        let source = searchText.isEmpty
            ? dataStore.codes
            : dataStore.codes.filter { code in
                code.label.localizedCaseInsensitiveContains(searchText) ||
                code.account.localizedCaseInsensitiveContains(searchText)
            }

        // Defensive: SwiftUI's List diffing asserts when two rows share an id,
        // so guarantee uniqueness before handing the array to ForEach.
        var seen = Set<UUID>()
        return source.filter { seen.insert($0.id).inserted }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 8) {
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
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 50)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search tokens")
            .navigationTitle("Autheris")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gear")
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
            .fullScreenCover(isPresented: $showingSettings) {
                SettingsView(dataStore: dataStore)
            }
            .alert(
                Text(importResult?.title ?? "Import"),
                isPresented: Binding(
                    get: { importResult != nil },
                    set: { if !$0 { importResult = nil } }
                ),
                presenting: importResult
            ) { _ in
                Button("OK") { importResult = nil }
            } message: { result in
                Text(result.body)
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
    @State private var showEditSheet = false
    @State private var showSecretSheet = false
    
    // Haptic feedback generators
    private let copyHaptic = UIImpactFeedbackGenerator(style: .light)
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

    private var isExpiring: Bool {
        remainingSeconds <= warningThreshold
    }

    private var countdownProgress: Double {
        guard code.period > 0 else { return 0 }
        return min(max(Double(remainingSeconds) / Double(code.period), 0), 1)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            IssuerIconView(branding: branding, size: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(code.label)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                if !code.account.isEmpty {
                    Text(code.account)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                if isCopied {
                    Label("Copied", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.accentColor)
                } else {
                    Text(code.currentCode)
                        .font(.system(.title2, design: .monospaced).weight(.bold))
                        .foregroundColor(isExpiring ? .red : .primary)
                }

                HStack(spacing: 6) {
                    ProgressView(value: countdownProgress)
                        .frame(width: 56)
                        .tint(isExpiring ? .red : timerRingColor)

                    Text("\(remainingSeconds)s")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(isExpiring ? .red : .secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    isExpiring ? Color.red.opacity(0.45) : Color(.separator).opacity(0.15),
                    lineWidth: isExpiring ? 1 : 0.5
                )
        )
        .onTapGesture {
            // Tap to copy with haptic feedback
            copyToClipboard()
        }
        .contextMenu {
            Button {
                copyToClipboard()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }

            Button {
                showSecretSheet = true
            } label: {
                Label("View Secret", systemImage: "key")
            }

            Button {
                showEditSheet = true
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            Button(role: .destructive) {
                // Haptic feedback for delete action
                deleteHaptic.notificationOccurred(.warning)
                deleteToken()
            } label: {
                Label("Delete", systemImage: "trash")
            }
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
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isExpiring)
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
        
        ClipboardHelper.copy(code.currentCode)
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
    
    private func deleteToken() {
        dataStore.removeCode(code)
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

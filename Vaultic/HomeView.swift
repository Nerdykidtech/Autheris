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
    
    /// The codes to show, in display order.
    ///
    /// `orderedCodes` already applies pinned-first ordering and de-duplication
    /// (SwiftUI's `List` diffing asserts when two rows share an id), so this only
    /// narrows by the search term.
    var filteredCodes: [OTPCode] {
        let ordered = dataStore.orderedCodes
        guard !searchText.isEmpty else { return ordered }

        return ordered.filter { code in
            code.label.localizedCaseInsensitiveContains(searchText) ||
            code.account.localizedCaseInsensitiveContains(searchText)
        }
    }

    /// Reordering a filtered list cannot be mapped back onto the stored order, so
    /// dragging is only offered while the whole list is on screen.
    private var canReorder: Bool {
        searchText.isEmpty && !filteredCodes.isEmpty
    }

    private var emptyState: some View {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if filteredCodes.isEmpty {
                    emptyState
                } else {
                    // The cards themselves are untouched; `List` is what makes them
                    // reorderable, and these row modifiers are what keep their
                    // existing plain look.
                    List {
                        ForEach(filteredCodes) { code in
                            OTPCardView(code: code, dataStore: dataStore)
                                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                        .onMove { offsets, destination in
                            dataStore.move(offsets: offsets, destination: destination)
                        }
                        .moveDisabled(!canReorder)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
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
                
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    // Reordering needs edit mode; hiding it while a search is
                    // active avoids a mode that would offer no handles.
                    if canReorder {
                        EditButton()
                    }

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
        return max(5, Int(Double(code.effectivePeriod) * 0.1667)) // 5 seconds or 1/6 of period
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
        // `effectivePeriod` is always positive, so this cannot divide by zero even
        // for a token whose stored period is malformed.
        return min(max(Double(remainingSeconds) / Double(code.effectivePeriod), 0), 1)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            IssuerIconView(branding: branding, size: 40)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    if code.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundColor(.accentColor)
                    }

                    Text(code.label)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(code.isPinned ? "\(code.label), pinned" : code.label)

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
                dataStore.setPinned(!code.isPinned, for: code)
            } label: {
                Label(code.isPinned ? "Unpin" : "Pin",
                      systemImage: code.isPinned ? "pin.slash" : "pin")
            }

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
        let period = Double(code.effectivePeriod)
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
    /// Seeded from the *effective* values, so opening this screen on a token whose
    /// stored digits or period is malformed shows something sane, and saving repairs
    /// it. `OTPGenerator` decides what "effective" means.
    @State private var algorithm: OTPAlgorithm
    @State private var digits: Int
    @State private var period: Int
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
        algorithm != code.algorithm ||
        digits != code.effectiveDigits ||
        period != code.effectivePeriod ||
        ringHexForSave() != code.timerRingHex
    }
    
    init(code: OTPCode, dataStore: OTPDataStore) {
        self.code = code
        self.dataStore = dataStore
        _label = State(initialValue: code.label)
        _account = State(initialValue: code.account)
        _algorithm = State(initialValue: code.algorithm)
        // Clamped into the ranges the steppers offer, so a malformed stored value
        // opens as a usable one rather than leaving a control out of range.
        _digits = State(initialValue: min(max(code.effectiveDigits, 6), 10))
        _period = State(initialValue: min(max(code.effectivePeriod, 15), 300))
        let branding = IssuerBranding.forLabel(code.label)
        if let hex = code.timerRingHex, let c = Color(hex: hex) {
            _ringColor = State(initialValue: c)
        } else {
            _ringColor = State(initialValue: branding.color)
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                headerSection
                identitySection
                codeSection
                appearanceSection
            }
            .formStyle(.grouped)
            .navigationTitle("Edit Token")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // `.cancellationAction` / `.confirmationAction` are SwiftUI's own
                // placements for a modal, so the system decides the position and the
                // emphasis of the confirming action rather than me guessing at it.
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if isDirty {
                            showDiscardConfirmation = true
                        } else {
                            dismiss()
                        }
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                    .disabled(!isDirty)
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

    // MARK: - Sections

    /// Issuer icon and a live code, so the effect of changing the algorithm or the
    /// period is visible immediately — and so a token that produces no code at all
    /// is obvious rather than something to discover later.
    private var headerSection: some View {
        Section {
            HStack(spacing: 14) {
                IssuerIconView(branding: previewBranding, size: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text(label.isEmpty ? code.label : label)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    if !account.isEmpty {
                        Text(account)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                // Ticks, so the preview does not sit frozen on a stale code.
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(previewCode)
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var identitySection: some View {
        Section {
            TextField("Service name", text: $label)

            TextField("Account (optional)", text: $account)
                .textContentType(.username)
                .autocapitalization(.none)
        }
    }

    private var codeSection: some View {
        Section {
            Picker("Algorithm", selection: $algorithm) {
                ForEach(OTPAlgorithm.allCases, id: \.self) { option in
                    Text(option.rawValue).tag(option)
                }
            }

            Stepper("Digits: \(digits)", value: $digits, in: 6...10)
            Stepper("Period: \(period) seconds", value: $period, in: 15...300, step: 15)
        } header: {
            Text("Code")
        } footer: {
            Text("Scanning a service's QR code fills these in. If your codes are rejected, check the service's instructions — most use SHA-1 and 30 seconds, but some (myGov, for example) need SHA-256.")
        }
    }

    private var appearanceSection: some View {
        Section {
            ColorPicker(selection: $ringColor, supportsOpacity: false) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .stroke(Color(.separator).opacity(0.35), lineWidth: 1)
                            .frame(width: 36, height: 36)
                        Circle()
                            .stroke(ringColor, lineWidth: 3)
                            .frame(width: 28, height: 28)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Ring color")
                        Text(ringColorMatchesBranding ? "Automatic (service color)" : "Custom color")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }

            Button("Use service default") {
                ringColor = editBranding.color
            }
            .disabled(ringColorMatchesBranding)
        } header: {
            Text("Appearance")
        }
    }

    /// The icon for what is currently typed, so a rename updates it.
    ///
    /// `editBranding` stays tied to the stored label, because `ringHexForSave` uses
    /// it to decide whether the chosen color counts as "automatic".
    private var previewBranding: IssuerBranding {
        IssuerBranding.forLabel(label.isEmpty ? code.label : label)
    }

    /// What the code would be with the values currently on screen, rather than the
    /// stored ones.
    private var previewCode: String {
        OTPGenerator.generateOTP(secret: code.secret, algorithm: algorithm,
                                 digits: digits, period: period)
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
        
        // Goes through `edited()` rather than rebuilding the token field by field,
        // so a field added later cannot be silently reset by this screen — which is
        // exactly what adding `isPinned` would otherwise have done.
        let updatedCode = code.edited(
            label: label,
            account: account,
            algorithm: algorithm,
            digits: digits,
            period: period,
            timerRingHex: .some(ringHexForSave())
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

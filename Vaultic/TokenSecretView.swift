import SwiftUI

/// Focused sheet to view, copy, or edit one token's setup key.
/// Editing requires an explicit Save; dismissing with unsaved changes asks for confirmation.
struct TokenSecretView: View {
    let code: OTPCode
    @ObservedObject var dataStore: OTPDataStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var secret: String
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var showDiscardConfirmation = false
    
    private var branding: IssuerBranding {
        IssuerBranding.forLabel(code.label)
    }
    
    private var isDirty: Bool {
        secret != code.secret
    }
    
    init(code: OTPCode, dataStore: OTPDataStore) {
        self.code = code
        self.dataStore = dataStore
        _secret = State(initialValue: code.secret)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()
                
                VStack(spacing: 16) {
                    HStack(spacing: 12) {
                        IssuerIconView(branding: branding)
                        
                        VStack(alignment: .leading, spacing: 1) {
                            Text(code.label)
                                .font(.system(size: 15, weight: .semibold))
                                .lineLimit(1)
                            
                            if !code.account.isEmpty {
                                Text(code.account)
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.separator), lineWidth: 1)
                    )
                    
                    SecretKeySection(title: "Setup Key", secret: $secret)
                }
                .padding(.horizontal, 32)
                
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
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
            }
            .navigationTitle("Account Secret")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .platformSheetLeading) {
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
                Text("Your edits to this setup key have not been saved.")
            }
            .alert("Error", isPresented: $showingAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
        }
        .platformSheetDetents(dragIndicator: true)
            .platformSheetSize()
    }
    
    private func saveChanges() {
        if !OTPGenerator.isValidSecret(secret) {
            alertMessage = String(localized: "Please enter a valid Base32 secret key (letters A-Z, numbers 2-7, minimum 16 characters).")
            showingAlert = true
            return
        }
        
        // `edited()` keeps every field this screen does not touch — including the
        // pin, which rebuilding the token by hand used to reset.
        let updatedCode = code.edited(secret: secret)
        
        if let index = dataStore.codes.firstIndex(where: { $0.id == code.id }) {
            dataStore.updateCode(updatedCode, at: index)
            Haptics.notify(.success)
        }
        
        dismiss()
    }
}
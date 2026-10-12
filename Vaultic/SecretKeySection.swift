import SwiftUI

/// Masked setup-key field: blurred by default, tap or eye icon to reveal,
/// with copy feedback and editing of the bound secret.
struct SecretKeySection: View {
    let title: LocalizedStringKey
    @Binding var secret: String
    
    @State private var isRevealed = false
    @State private var isCopied = false
    
    /// Fixed-width bullets so the masked field doesn't jump when the secret length changes.
    private var maskedText: String {
        String(repeating: "•", count: max(8, min(secret.count, 24)))
    }

    /// Typed explicitly so the two literals are looked up rather than rendered
    /// verbatim — a ternary on its own infers as `String`.
    private var revealToggleLabel: LocalizedStringKey {
        isRevealed ? "Hide setup key" : "Reveal setup key"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Button {
                    Haptics.impact(.light)
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isRevealed.toggle()
                    }
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(revealToggleLabel)
            }
            
            Group {
                if isRevealed {
                    TextField("Setup key", text: $secret)
                        .platformNoAutocapitalization()
                        .autocorrectionDisabled()
                        .platformSetupKeyContentType()
                        .asciiCapableKeyboard()
                        .font(.body.monospaced().weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.primary)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(.secondarySystemBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color(.separator), lineWidth: 1)
                        )
                } else {
                    Button {
                        Haptics.impact(.light)
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isRevealed = true
                        }
                    } label: {
                        Text(maskedText)
                            .font(.body.monospaced().weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(.secondarySystemBackground))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color(.separator), lineWidth: 1)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Setup key hidden")
                    .accessibilityHint("Reveals the setup key")
                }
            }
            
            HStack {
                Button {
                    Haptics.impact(.light)
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isRevealed.toggle()
                    }
                } label: {
                    Label(isRevealed ? "Hide" : "Show", systemImage: isRevealed ? "eye.slash" : "eye")
                        .font(.footnote.weight(.medium))
                }
                .buttonStyle(.bordered)
                
                Button {
                    copySecret()
                } label: {
                    Label(isCopied ? "Copied" : "Copy", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.footnote.weight(.medium))
                }
                .buttonStyle(.bordered)
                .disabled(secret.isEmpty)
                
                Spacer()
            }
        }
    }
    
    private func copySecret() {
        guard !secret.isEmpty else { return }
        Haptics.impact(.light)
        ClipboardHelper.copy(secret)
        withAnimation(.easeInOut(duration: 0.2)) {
            isCopied = true
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeInOut(duration: 0.2)) {
                isCopied = false
            }
        }
    }
}
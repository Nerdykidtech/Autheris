import SwiftUI

/// Masked setup-key field: blurred by default, tap or eye icon to reveal,
/// with copy feedback and editing of the bound secret.
struct SecretKeySection: View {
    let title: String
    @Binding var secret: String
    
    @State private var isRevealed = false
    @State private var isCopied = false
    
    /// Fixed-width bullets so the masked field doesn't jump when the secret length changes.
    private var maskedText: String {
        String(repeating: "•", count: max(8, min(secret.count, 24)))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button {
                    Haptics.impact(.light)
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isRevealed.toggle()
                    }
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isRevealed ? "Hide setup key" : "Reveal setup key")
            }
            
            Group {
                if isRevealed {
                    TextField("Setup key", text: $secret)
                        .platformNoAutocapitalization()
                        .autocorrectionDisabled()
                        .platformTextContentType(.password)
                        .asciiCapableKeyboard()
                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundColor(.primary)
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
                    Text(maskedText)
                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
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
                        .onTapGesture {
                            Haptics.impact(.light)
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isRevealed = true
                            }
                        }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel("Setup key hidden")
                        .accessibilityHint("Tap to reveal the setup key")
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeInOut(duration: 0.2)) {
                isCopied = false
            }
        }
    }
}
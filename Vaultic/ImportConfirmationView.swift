import SwiftUI

/// Sends codes to the app's one import review: `ImportConfirmationView`, which
/// `AutherisApp` shows once the app is unlocked and which adds nothing until the
/// user taps Import.
///
/// Links reach it directly. This is how the scanner reaches it, so a batch of
/// codes from a QR code waits behind App Lock exactly as one from a link does,
/// instead of being held by a screen that App Lock tears down.
struct ReviewImportAction {
    let review: @MainActor ([OTPCode]) -> Void

    @MainActor func callAsFunction(_ tokens: [OTPCode]) {
        review(tokens)
    }
}

extension EnvironmentValues {
    @Entry var reviewImport = ReviewImportAction { _ in
        assertionFailure("reviewImport is only set by AutherisApp")
    }
}

struct ImportConfirmationView: View {
    /// Codes that arrived in a link, not yet in the vault. See `IncomingLink`.
    let tokens: [OTPCode]
    @ObservedObject var dataStore: OTPDataStore
    @Binding var isPresented: Bool
    @State private var importResult: ImportResult?
    
    enum ImportResult {
        case success(total: Int, new: Int, duplicates: Int)
        case allDuplicates(Int)
    }
    
    var body: some View {
        GeometryReader { proxy in
            let targetHeight = min(proxy.size.height * 0.55, 520)

            VStack(spacing: 0) {
                // Top handle (iOS-style)
                Capsule()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 40, height: 5)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                
                // Content area with dynamic sizing
                Group {
                    if let result = importResult {
                        resultView(for: result)
                    } else {
                        confirmationView
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                
                // Bottom padding for spacing
                Spacer(minLength: 40)
            }
            .frame(maxWidth: .infinity)
            .readableWidth(ReadableWidth.prose)
            .frame(height: targetHeight, alignment: .top)
            .background(
                Color(.systemBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .ignoresSafeArea(edges: .bottom)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.15), radius: 30, x: 0, y: -5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        // The card is drawn light. `preferredColorScheme` would say so for the
        // whole window — flipping the app behind the card to light mode for as
        // long as it was up — so the environment is set for the card alone.
        .environment(\.colorScheme, .light)
    }
    
    // MARK: - Subviews
    
    /// Shown first, every time. A link can come from another app or a web page,
    /// so the user sees exactly what it would add before anything is written.
    private var confirmationView: some View {
        VStack(spacing: 20) {
            // Icon
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 44))
                .foregroundColor(.accentColor)
                .symbolRenderingMode(.hierarchical)
            
            // Title
            Text("Import Tokens")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            // Description
            Text("A link is asking to add these codes to Autheris. Only import them if you expected this.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            // What would be added, verbatim
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(tokens) { token in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: token.label)
                                .font(.callout.weight(.semibold))
                                .foregroundColor(.primary)
                            if !token.account.isEmpty {
                                Text(verbatim: token.account)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxHeight: 120)
            
            // Buttons
            VStack(spacing: 12) {
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        importTokens()
                    }
                }) {
                    Text("Import")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            Capsule()
                                .fill(Color.accentColor)
                        )
                }
                
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isPresented = false
                    }
                }) {
                    Text("Cancel")
                        .font(.headline)
                        .foregroundColor(.accentColor)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            Capsule()
                                .stroke(Color.accentColor, lineWidth: 2)
                        )
                }
            }
        }
    }
    
    private func resultView(for result: ImportResult) -> some View {
        VStack(spacing: 24) {
            Group {
                switch result {
                case .success(let total, let new, let duplicates):
                    successView(total: total, new: new, duplicates: duplicates)
                case .allDuplicates(let count):
                    duplicatesView(count: count)
                }
            }
        }
        .padding(.vertical, 40)
    }
    
    private func successView(total: Int, new: Int, duplicates: Int) -> some View {
        VStack(spacing: 20) {
            // Success icon
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundColor(.green)
                .symbolRenderingMode(.hierarchical)
            
            // Title
            Text("Import Successful")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            // Stats
            VStack(spacing: 12) {
                statRow(
                    label: "Total scanned:",
                    value: "\(total) tokens",
                    color: .primary
                )
                
                if new > 0 {
                    statRow(
                        label: "Added:",
                        value: "\(new) new tokens",
                        color: .green,
                        icon: "plus.circle.fill"
                    )
                }
                
                if duplicates > 0 {
                    statRow(
                        label: "Skipped:",
                        value: "\(duplicates) duplicates",
                        color: .orange,
                        icon: "xmark.circle.fill"
                    )
                }
            }
            .font(.callout)
            
            // Note
            Text("Check your home screen for the new tokens!")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
            
            // Done button
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isPresented = false
                }
            }) {
                Text("Done")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        Capsule()
                            .fill(Color.accentColor)
                    )
            }
            .padding(.top, 8)
        }
    }
    
    private func duplicatesView(count: Int) -> some View {
        VStack(spacing: 20) {
            // Info icon
            Image(systemName: "info.circle.fill")
                .font(.system(size: 52))
                .foregroundColor(.orange)
                .symbolRenderingMode(.hierarchical)
            
            // Title
            Text("Tokens Already Exist")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            // Message
            Text("All \(count) tokens in this import already exist on your device.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            
            // Done button
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isPresented = false
                }
            }) {
                Text("Done")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        Capsule()
                            .fill(Color.accentColor)
                    )
            }
            .padding(.top, 8)
        }
    }
    
    private func statRow(label: LocalizedStringKey, value: LocalizedStringKey, color: Color, icon: String? = nil) -> some View {
        HStack(spacing: 8) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(color)
            }
            
            Text(label)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
        .font(.callout)
    }
    
    // MARK: - Import Logic
    
    /// The only place a link's codes reach the vault, and only from the Import
    /// button above.
    private func importTokens() {
        let result = dataStore.addCodes(tokens)

        guard result.added > 0 else {
            importResult = .allDuplicates(tokens.count)
            return
        }

        importResult = .success(
            total: tokens.count,
            new: result.added,
            duplicates: result.skipped
        )
    }
}

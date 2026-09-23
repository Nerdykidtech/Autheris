import SwiftUI

struct ImportConfirmationView: View {
    let data: Data
    @ObservedObject var dataStore: OTPDataStore
    @Binding var isPresented: Bool
    @State private var importResult: ImportResult?
    @State private var isImporting = true
    @State private var debugInfo: String = ""
    @State private var hasStartedImport = false
    
    enum ImportResult {
        case success(total: Int, new: Int, duplicates: Int)
        case failure(String)
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
                        importingView
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
        .task {
            guard !hasStartedImport else { return }
            hasStartedImport = true
            #if DEBUG
            print("ImportConfirmationView appeared with data size: \(data.count) bytes")
            #endif
            isImporting = true
            processImport()
        }
        .preferredColorScheme(.light)
    }
    
    // MARK: - Subviews
    
    private var importingView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.3)
                .tint(.accentColor)
            
            VStack(spacing: 8) {
                Text("Importing tokens...")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text(debugInfo)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .padding(.vertical, 40)
    }
    
    private var confirmationView: some View {
        VStack(spacing: 24) {
            // Icon
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 52))
                .foregroundColor(.accentColor)
                .symbolRenderingMode(.hierarchical)
            
            // Title
            Text("Import Tokens")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            // Description
            Text("You've scanned a QR code with authentication tokens. Would you like to import them?")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            
            // Buttons
            VStack(spacing: 12) {
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isImporting = true
                        processImport()
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
        .padding(.vertical, 40)
    }
    
    private func resultView(for result: ImportResult) -> some View {
        VStack(spacing: 24) {
            Group {
                switch result {
                case .success(let total, let new, let duplicates):
                    successView(total: total, new: new, duplicates: duplicates)
                case .allDuplicates(let count):
                    duplicatesView(count: count)
                case .failure(let message):
                    failureView(message: message)
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
                    value: "\(total) token\(total == 1 ? "" : "s")",
                    color: .primary
                )
                
                if new > 0 {
                    statRow(
                        label: "Added:",
                        value: "\(new) new token\(new == 1 ? "" : "s")",
                        color: .green,
                        icon: "plus.circle.fill"
                    )
                }
                
                if duplicates > 0 {
                    statRow(
                        label: "Skipped:",
                        value: "\(duplicates) duplicate\(duplicates == 1 ? "" : "s")",
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
            Text("All \(count) token\(count == 1 ? "" : "s") in this import already exist on your device.")
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
    
    private func failureView(message: String) -> some View {
        VStack(spacing: 20) {
            // Error icon
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 52))
                .foregroundColor(.red)
                .symbolRenderingMode(.hierarchical)
            
            // Title
            Text("Import Failed")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            // Error message
            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            
            // Buttons
            VStack(spacing: 12) {
                Button(action: {
                    importResult = nil
                    isImporting = true
                    processImport()
                }) {
                    Text("Try Again")
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
            .padding(.top, 8)
        }
    }
    
    private func statRow(label: String, value: String, color: Color, icon: String? = nil) -> some View {
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
    
    private func processImport() {
        #if DEBUG
        print("Starting import process...")
        debugInfo = "Parsing QR code data..."
        #endif

        // Snapshot the existing tokens while still on the main actor. The parsing
        // below runs on a global queue, and store state is main-actor isolated, so
        // it cannot be read from there. The import sheet is modal, so nothing can
        // change the store while the parse is in flight.
        let existingTokens = dataStore.codes
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Try to decode as ExportData
                if let exportData = try? JSONDecoder().decode(ExportData.self, from: data) {
                    #if DEBUG
                    print("Successfully parsed ExportData with \(exportData.tokens.count) tokens")
                    #endif
                    
                    DispatchQueue.main.async {
                        #if DEBUG
                        self.debugInfo = "Found \(exportData.tokens.count) tokens. Checking for duplicates..."
                        #endif
                    }
                    
                    // Check for duplicates
                    #if DEBUG
                    print("Existing tokens count: \(existingTokens.count)")
                    #endif
                    
                    let newTokens = exportData.tokens.filter { newToken in
                        // Check if token already exists by label AND account
                        let isDuplicate = existingTokens.contains { existingToken in
                            existingToken.label == newToken.label && existingToken.account == newToken.account
                        }
                        
                        return !isDuplicate
                    }
                    
                    #if DEBUG
                    print("Found \(newTokens.count) new tokens out of \(exportData.tokens.count) total")
                    #endif
                    
                    DispatchQueue.main.async {
                        self.isImporting = false
                        
                        if newTokens.isEmpty {
                            self.importResult = .allDuplicates(exportData.tokens.count)
                        } else {
                            // Add new tokens
                            #if DEBUG
                            print("Adding \(newTokens.count) new tokens to data store")
                            #endif
                            for token in newTokens {
                                #if DEBUG
                                print("Adding token: \(token.label) - \(token.account)")
                                #endif
                                self.dataStore.addCode(token)
                            }
                            
                            // Force save to ensure changes are persisted
                            self.dataStore.saveCodes()
                            
                            // Post notification to refresh UI
                            NotificationCenter.default.post(
                                name: Notification.Name("TokensImported"),
                                object: newTokens.count
                            )
                            
                            self.importResult = .success(
                                total: exportData.tokens.count,
                                new: newTokens.count,
                                duplicates: exportData.tokens.count - newTokens.count
                            )
                        }
                    }
                } else {
                    // Try old format (plain array of OTPCode)
                    let importedCodes = try JSONDecoder().decode([OTPCode].self, from: data)
                    #if DEBUG
                    print("Successfully parsed as plain array with \(importedCodes.count) tokens")
                    #endif
                    
                    DispatchQueue.main.async {
                        #if DEBUG
                        self.debugInfo = "Found \(importedCodes.count) tokens. Checking for duplicates..."
                        #endif
                    }
                    
                    // Check for duplicates
                    #if DEBUG
                    print("Existing tokens count: \(existingTokens.count)")
                    #endif
                    
                    let newTokens = importedCodes.filter { newToken in
                        // Check if token already exists by label AND account
                        let isDuplicate = existingTokens.contains { existingToken in
                            existingToken.label == newToken.label && existingToken.account == newToken.account
                        }
                        
                        return !isDuplicate
                    }
                    
                    #if DEBUG
                    print("Found \(newTokens.count) new tokens out of \(importedCodes.count) total")
                    #endif
                    
                    DispatchQueue.main.async {
                        self.isImporting = false
                        
                        if newTokens.isEmpty {
                            self.importResult = .allDuplicates(importedCodes.count)
                        } else {
                            // Add new tokens
                            #if DEBUG
                            print("Adding \(newTokens.count) new tokens to data store")
                            #endif
                            for token in newTokens {
                                #if DEBUG
                                print("Adding token: \(token.label) - \(token.account)")
                                #endif
                                self.dataStore.addCode(token)
                            }
                            
                            // Force save to ensure changes are persisted
                            self.dataStore.saveCodes()
                            
                            // Post notification to refresh UI
                            NotificationCenter.default.post(
                                name: Notification.Name("TokensImported"),
                                object: newTokens.count
                            )
                            
                            self.importResult = .success(
                                total: importedCodes.count,
                                new: newTokens.count,
                                duplicates: importedCodes.count - newTokens.count
                            )
                        }
                    }
                }
            } catch {
                #if DEBUG
                print("Failed to parse import data: \(error)")
                #endif
                DispatchQueue.main.async {
                    self.isImporting = false
                    self.importResult = .failure("Could not parse the import data. The QR code may be corrupted or in an unsupported format.")
                }
            }
        }
    }
}


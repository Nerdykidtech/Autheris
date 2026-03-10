import SwiftUI

struct ImportConfirmationView: View {
    let data: Data
    @ObservedObject var dataStore: OTPDataStore
    @Binding var isPresented: Bool
    @State private var importResult: ImportResult?
    @State private var isImporting = false
    @State private var debugInfo: String = ""
    
    enum ImportResult {
        case success(total: Int, new: Int, duplicates: Int)
        case failure(String)
        case allDuplicates(Int)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if isImporting {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        
                        Text("Importing tokens...")
                            .font(.headline)
                        
                        Text(debugInfo)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let result = importResult {
                    switch result {
                    case .success(let total, let new, let duplicates):
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.green)
                        
                        Text("Import Successful")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        VStack(spacing: 8) {
                            Text("**Total scanned:** \(total) token\(total == 1 ? "" : "s")")
                            
                            if new > 0 {
                                Text("**Added:** \(new) new token\(new == 1 ? "" : "s")")
                                    .foregroundColor(.green)
                                    .fontWeight(.bold)
                            }
                            
                            if duplicates > 0 {
                                Text("**Skipped:** \(duplicates) duplicate\(duplicates == 1 ? "" : "s")")
                                    .foregroundColor(.orange)
                            }
                        }
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        
                        Text("Check your home screen for the new tokens!")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                        
                        Button("Done") {
                            isPresented = false
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top)
                        
                    case .allDuplicates(let count):
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.orange)
                        
                        Text("Tokens Already Exist")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("All \(count) token\(count == 1 ? "" : "s") in this import already exist on your device.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Button("Done") {
                            isPresented = false
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top)
                        
                    case .failure(let message):
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.red)
                        
                        Text("Import Failed")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text(message)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Button("Try Again") {
                            importResult = nil
                            isImporting = true
                            processImport()
                        }
                        .buttonStyle(.bordered)
                        .padding(.top)
                        
                        Button("Cancel") {
                            isPresented = false
                        }
                        .buttonStyle(.bordered)
                        .padding(.top, 4)
                    }
                } else {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 60))
                        .foregroundColor(.accentColor)
                    
                    Text("Import Tokens")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("You've scanned a QR code with authentication tokens. Would you like to import them?")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    HStack(spacing: 16) {
                        Button("Cancel") {
                            isPresented = false
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Import") {
                            isImporting = true
                            processImport()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.top)
                }
            }
            .padding(40)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
            .onAppear {
                print("ImportConfirmationView appeared with data size: \(data.count) bytes")
                
                // Auto-start import after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if importResult == nil && !isImporting {
                        isImporting = true
                        processImport()
                    }
                }
            }
        }
    }
    
    private func processImport() {
        print("Starting import process...")
        debugInfo = "Parsing QR code data..."
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Try to decode as ExportData
                if let exportData = try? JSONDecoder().decode(ExportData.self, from: data) {
                    print("Successfully parsed ExportData with \(exportData.tokens.count) tokens")
                    
                    DispatchQueue.main.async {
                        self.debugInfo = "Found \(exportData.tokens.count) tokens. Checking for duplicates..."
                    }
                    
                    // Check for duplicates
                    let existingTokens = self.dataStore.codes
                    print("Existing tokens count: \(existingTokens.count)")
                    
                    let newTokens = exportData.tokens.filter { newToken in
                        // Check if token already exists by label AND account
                        let isDuplicate = existingTokens.contains { existingToken in
                            existingToken.label == newToken.label && existingToken.account == newToken.account
                        }
                        
                        return !isDuplicate
                    }
                    
                    print("Found \(newTokens.count) new tokens out of \(exportData.tokens.count) total")
                    
                    DispatchQueue.main.async {
                        self.isImporting = false
                        
                        if newTokens.isEmpty {
                            self.importResult = .allDuplicates(exportData.tokens.count)
                        } else {
                            // Add new tokens
                            print("Adding \(newTokens.count) new tokens to data store")
                            for token in newTokens {
                                print("Adding token: \(token.label) - \(token.account)")
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
                    print("Successfully parsed as plain array with \(importedCodes.count) tokens")
                    
                    DispatchQueue.main.async {
                        self.debugInfo = "Found \(importedCodes.count) tokens. Checking for duplicates..."
                    }
                    
                    // Check for duplicates
                    let existingTokens = self.dataStore.codes
                    print("Existing tokens count: \(existingTokens.count)")
                    
                    let newTokens = importedCodes.filter { newToken in
                        // Check if token already exists by label AND account
                        let isDuplicate = existingTokens.contains { existingToken in
                            existingToken.label == newToken.label && existingToken.account == newToken.account
                        }
                        
                        return !isDuplicate
                    }
                    
                    print("Found \(newTokens.count) new tokens out of \(importedCodes.count) total")
                    
                    DispatchQueue.main.async {
                        self.isImporting = false
                        
                        if newTokens.isEmpty {
                            self.importResult = .allDuplicates(importedCodes.count)
                        } else {
                            // Add new tokens
                            print("Adding \(newTokens.count) new tokens to data store")
                            for token in newTokens {
                                print("Adding token: \(token.label) - \(token.account)")
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
                print("Failed to parse import data: \(error)")
                DispatchQueue.main.async {
                    self.isImporting = false
                    self.importResult = .failure("Could not parse the import data. The QR code may be corrupted or in an unsupported format.")
                }
            }
        }
    }
}

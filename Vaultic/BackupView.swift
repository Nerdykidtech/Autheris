import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct BackupView: View {
    @ObservedObject var dataStore: OTPDataStore
    @Environment(\.dismiss) private var dismiss
    @State private var backups: [URL] = []
    @State private var showingCreateBackupAlert = false
    @State private var showingDeleteAlert = false
    @State private var backupToDelete: URL?
    @State private var showingRestoreAlert = false
    @State private var backupToRestore: URL?
    @State private var showingImportAlert = false
    @State private var isImportingFile = false
    @State private var shareURL: URL?
    @State private var showingShareSheet = false
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(action: createBackup) {
                        Label("Create New Backup", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .foregroundColor(.accentColor)
                    }
                    
                    Button(action: { isImportingFile = true }) {
                        Label("Import Backup from File", systemImage: "square.and.arrow.down")
                            .font(.headline)
                            .foregroundColor(.accentColor)
                    }
                }
                
                if !backups.isEmpty {
                    Section("Available Backups") {
                        ForEach(backups, id: \.self) { backupURL in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(backupURL.lastPathComponent)
                                        .font(.system(.body, design: .monospaced))
                                        .lineLimit(1)
                                    
                                    if let date = getCreationDate(for: backupURL) {
                                        Text(date, style: .date)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Text(formatFileSize(for: backupURL))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Menu {
                                    Button(action: { 
                                        backupToRestore = backupURL
                                        showingRestoreAlert = true 
                                    }) {
                                        Label("Restore", systemImage: "arrow.counterclockwise")
                                    }
                                    
                                    Button(action: { shareBackup(backupURL) }) {
                                        Label("Share", systemImage: "square.and.arrow.up")
                                    }
                                    
                                    Button(role: .destructive, action: { 
                                        backupToDelete = backupURL
                                        showingDeleteAlert = true 
                                    }) {
                                        Label("Delete", systemImage: "trash")
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } else {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "externaldrive")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)
                                .opacity(0.5)
                            
                            Text("No Backups Yet")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            Text("Create your first backup to save all your tokens")
                                .font(.subheadline)
                                .foregroundColor(.secondary.opacity(0.8))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                    }
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Backup Information")
                            .font(.headline)
                        
                        Text("Backups are stored locally on your device in the app's documents folder. They contain all your OTP tokens in encrypted format.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("Note: Backups do not sync via iCloud. For device transfer, use the QR code export feature.")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("Backup & Restore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                refreshBackups()
            }
            .alert("Backup Created", isPresented: $showingCreateBackupAlert) {
                Button("Share") {
                    if shareURL != nil {
                        showingShareSheet = true
                    }
                }
                Button("OK", role: .cancel) { }
            } message: {
                Text("Your tokens have been backed up successfully.")
            }
            .alert("Delete Backup", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    if let backupURL = backupToDelete {
                        if dataStore.deleteBackup(at: backupURL) {
                            refreshBackups()
                        }
                    }
                }
            } message: {
                Text("Are you sure you want to delete this backup?")
            }
            .alert("Restore Backup", isPresented: $showingRestoreAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Restore", role: .destructive) {
                    if let backupURL = backupToRestore {
                        if dataStore.restoreFromBackup(at: backupURL) {
                            dismiss()
                        }
                    }
                }
            } message: {
                Text("Restoring will replace all current tokens with the backup. This cannot be undone.")
            }
            .fileImporter(isPresented: $isImportingFile, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    if url.startAccessingSecurityScopedResource() {
                        defer { url.stopAccessingSecurityScopedResource() }
                        
                        if dataStore.restoreFromBackup(at: url) {
                            dismiss()
                        }
                    }
                case .failure(let error):
                    print("Failed to import file: \(error)")
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let shareURL {
                    ShareSheet(activityItems: [shareURL])
                } else {
                    Text("Nothing to share.")
                        .presentationDetents([.medium])
                }
            }
        }
    }
    
    private func refreshBackups() {
        backups = dataStore.listBackups()
    }
    
    private func createBackup() {
        if let url = dataStore.createBackup() {
            refreshBackups()
            shareURL = url
            showingCreateBackupAlert = true
        }
    }
    
    private func getCreationDate(for url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.creationDateKey]).creationDate
    }
    
    private func formatFileSize(for url: URL) -> String {
        do {
            let resources = try url.resourceValues(forKeys: [.fileSizeKey])
            let size = resources.fileSize ?? 0
            
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            return formatter.string(fromByteCount: Int64(size))
        } catch {
            return "Unknown size"
        }
    }
    
    private func shareBackup(_ backupURL: URL) {
        shareURL = backupURL
        showingShareSheet = true
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

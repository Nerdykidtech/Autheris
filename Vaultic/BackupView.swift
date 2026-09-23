import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

private func backupFileSizeText(_ url: URL) -> String {
    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: Int64(size))
}

private func backupCreationDate(_ url: URL) -> Date? {
    try? url.resourceValues(forKeys: [.creationDateKey]).creationDate
}

private struct BackupRowView: View {
    let backupURL: URL
    let onRestore: () -> Void
    let onShare: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(backupURL.lastPathComponent)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)

                if let date = backupCreationDate(backupURL) {
                    Text(date, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text(backupFileSizeText(backupURL))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Menu {
                Button(action: onRestore) {
                    Label("Restore", systemImage: "arrow.counterclockwise")
                }

                Button(action: onShare) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }

                Button(role: .destructive, action: onDelete) {
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

struct BackupView: View {
    @ObservedObject var dataStore: OTPDataStore
    @Environment(\.dismiss) private var dismiss
    @State private var backups: [URL] = []
    @State private var showingCreateBackupAlert = false
    @State private var showingCreatePasswordAlert = false
    @State private var newBackupPassword = ""
    @State private var newBackupConfirmPassword = ""
    @State private var showingDeleteAlert = false
    @State private var backupToDelete: URL?
    @State private var showingRestoreAlert = false
    @State private var backupToRestore: URL?
    @State private var showingPasswordAlert = false
    @State private var backupPassword = ""
    @State private var showingRestoreError = false
    @State private var restoreErrorMessage = ""
    @State private var isImportingFile = false
    @State private var shareURL: URL?
    @State private var showingShareSheet = false

    var body: some View {
        NavigationStack {
            List {
                actionSection

                if !backups.isEmpty {
                    backupsSection
                } else {
                    emptyStateSection
                }

                backupInfoSection
            }
            .navigationTitle("Backup & Restore")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .platformSheetTrailing) {
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
            .alert("Create Encrypted Backup", isPresented: $showingCreatePasswordAlert) {
                SecureField("Password", text: $newBackupPassword)
                SecureField("Confirm Password", text: $newBackupConfirmPassword)
                Button("Create") {
                    createEncryptedBackup()
                }
                Button("Cancel", role: .cancel) {
                    newBackupPassword = ""
                    newBackupConfirmPassword = ""
                }
            } message: {
                Text("Choose a password. You'll need it to restore this backup.")
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
            .alert("Enter Backup Password", isPresented: $showingPasswordAlert) {
                SecureField("Password", text: $backupPassword)
                Button("Restore") {
                    restoreEncryptedBackup()
                }
                Button("Cancel", role: .cancel) {
                    backupPassword = ""
                }
            } message: {
                Text("This backup is encrypted. Enter the password used when it was created.")
            }
            .alert("Restore Failed", isPresented: $showingRestoreError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(restoreErrorMessage)
            }
            .fileImporter(
                isPresented: $isImportingFile,
                allowedContentTypes: backupContentTypes
            ) { result in
                handleFileImport(result)
            }
            .sheet(isPresented: $showingShareSheet) {
                if let shareURL {
                    PlatformShareSheet(activityItems: [shareURL])
                } else {
                    Text("Nothing to share.")
                        .platformSheetDetents([.medium])
                        .platformSheetSize(minHeight: 200)
                }
            }
        }
        .platformSheetSize(minHeight: 560)
    }

    // MARK: - Sections

    private var actionSection: some View {
        Section {
            Button {
                showingCreatePasswordAlert = true
            } label: {
                Label("Create Encrypted Backup", systemImage: "lock.doc.fill")
                    .font(.headline)
                    .foregroundColor(.accentColor)
            }

            Button(action: createBackup) {
                Label("Create Unencrypted Backup", systemImage: "doc.badge.plus")
                    .font(.subheadline)
            }

            Button(action: { isImportingFile = true }) {
                Label("Import Backup from File", systemImage: "square.and.arrow.down")
                    .font(.subheadline)
            }
        }
    }

    private var backupsSection: some View {
        Section("Available Backups") {
            ForEach(backups, id: \.self) { backupURL in
                BackupRowView(
                    backupURL: backupURL,
                    onRestore: { prepareRestore(backupURL) },
                    onShare: { shareBackup(backupURL) },
                    onDelete: {
                        backupToDelete = backupURL
                        showingDeleteAlert = true
                    }
                )
            }
        }
    }

    private var emptyStateSection: some View {
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

    private var backupInfoSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Backup Information")
                    .font(.headline)

                Text("Encrypted backups (.autheris) are protected with your password using AES-GCM. Unencrypted backups are plain JSON.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("Note: Backups do not sync via iCloud. For device transfer, use the QR code export feature.")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
            .padding(.vertical, 8)
        }
    }

    private var backupContentTypes: [UTType] {
        var types: [UTType] = [.json]
        if let autherisType = UTType(filenameExtension: "autheris") {
            types.append(autherisType)
        } else {
            types.append(.data)
        }
        return types
    }

    // MARK: - Actions

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

    private func createEncryptedBackup() {
        guard !newBackupPassword.isEmpty, newBackupPassword == newBackupConfirmPassword else {
            restoreErrorMessage = "Passwords don't match. Please try again."
            showingRestoreError = true
            return
        }

        if let url = dataStore.createEncryptedBackup(password: newBackupPassword) {
            refreshBackups()
            shareURL = url
            showingCreateBackupAlert = true
        } else {
            restoreErrorMessage = "Could not create the encrypted backup."
            showingRestoreError = true
        }

        newBackupPassword = ""
        newBackupConfirmPassword = ""
    }

    private func prepareRestore(_ backupURL: URL) {
        backupToRestore = backupURL
        if backupURL.pathExtension.lowercased() == "autheris" {
            backupPassword = ""
            showingPasswordAlert = true
        } else {
            showingRestoreAlert = true
        }
    }

    private func restoreEncryptedBackup() {
        guard let backupURL = backupToRestore, !backupPassword.isEmpty else { return }

        if dataStore.restoreFromBackup(at: backupURL, password: backupPassword) {
            dismiss()
        } else {
            restoreErrorMessage = "Incorrect password or corrupted backup."
            showingRestoreError = true
        }
        backupPassword = ""
    }

    private func handleFileImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let didStartAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            prepareRestore(url)
        case .failure(let error):
            #if DEBUG
            print("Failed to import file: \(error)")
            #endif
        }
    }

    private func shareBackup(_ backupURL: URL) {
        shareURL = backupURL
        showingShareSheet = true
    }
}

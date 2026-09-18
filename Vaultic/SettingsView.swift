import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var dataStore: OTPDataStore
    @AppStorage("enablePrivacyBlur") private var enablePrivacyBlur = true
    @AppStorage("hideCodesInAppSwitcher") private var hideCodesInAppSwitcher = true
    /// Same key `OTPDataStore` owns, so the toggle and the sync engine cannot drift.
    @AppStorage(OTPDataStore.syncEnabledKey) private var isICloudSyncEnabled = false

    @State private var showingTeardownDialog = false
    @State private var showingDeleteCloudDataDialog = false
    @State private var syncErrorMessage: String?

    private var appMarketingVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "—"
    }
    
    private var appBuildNumber: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "—"
    }

    /// Intercepts the toggle so turning sync *off* can ask how to tear down first,
    /// rather than silently discarding the user's iCloud copy.
    private var syncToggleBinding: Binding<Bool> {
        Binding(
            get: { isICloudSyncEnabled },
            set: { newValue in
                if newValue {
                    isICloudSyncEnabled = true
                    dataStore.setSyncEnabled(true)
                } else {
                    showingTeardownDialog = true
                }
            }
        )
    }

    private var statusTint: Color {
        switch dataStore.syncStatus {
        case .synced: return .green
        case .syncing: return .secondary
        case .disabled: return .secondary
        case .waitingForNetwork: return .orange
        case .accountUnavailable: return .orange
        case .unavailable: return .red
        case .failed: return .red
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Sync with iCloud", isOn: syncToggleBinding)
                        .toggleStyle(SwitchToggleStyle(tint: .accentColor))

                    syncStatusRow

                    if !dataStore.isSyncAvailable && !isICloudSyncEnabled {
                        // Explain, but do not block: the toggle must stay usable, and
                        // the status row reports the precise reason if it fails.
                        Text("iCloud isn't reachable right now. You can still turn sync on — it will connect once iCloud is available.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if isICloudSyncEnabled {
                        Button(role: .destructive) {
                            showingDeleteCloudDataDialog = true
                        } label: {
                            Text("Delete Tokens from iCloud")
                        }
                    }
                } header: {
                    Text("iCloud Sync")
                } footer: {
                    Text("Syncs your tokens through your private iCloud database. Secret keys are end-to-end encrypted and are never stored in a readable form.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }

                Section {
                    Toggle("Blur when backgrounded", isOn: $enablePrivacyBlur)
                        .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                    
                    Toggle("Hide codes in app switcher", isOn: $hideCodesInAppSwitcher)
                        .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                } header: {
                    Text("Privacy")
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("• **Blur when backgrounded**: Automatically blurs the app when you switch to another app or go to the home screen.")
                        Text("• **Hide codes in app switcher**: Shows a privacy screen instead of your OTP codes when using the app switcher.")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
                }
                
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appMarketingVersion)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    
                    HStack {
                        Text("Build")
                        Spacer()
                        Text(appBuildNumber)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    
                    HStack {
                        Text("Made By")
                        Spacer()
                        Text("Hunter Eddington")
                            .foregroundColor(.secondary)
                    }
                    
                    Link(destination: URL(string: "https://eddington.tech/autheris")!) {
                        HStack {
                            Text("Website")
                            Spacer()
                            Text("eddington.tech/autheris")
                                .foregroundColor(.secondary)
                            Image(systemName: "arrow.up.right")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            // Re-check the iCloud account each time Settings opens, so a user who
            // signed in while the app was running sees the toggle enabled.
            await dataStore.refreshSyncAvailability()
        }
        .confirmationDialog(
            "Turn off iCloud Sync?",
            isPresented: $showingTeardownDialog,
            titleVisibility: .visible
        ) {
            Button("Keep Tokens on This Device") {
                isICloudSyncEnabled = false
                dataStore.setSyncEnabled(false)
            }
            Button("Delete Tokens from iCloud", role: .destructive) {
                Task { await teardown(deleteCloudData: true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Tokens stay on this device either way. Deleting from iCloud also removes them from your other devices.")
        }
        .confirmationDialog(
            "Delete Tokens from iCloud?",
            isPresented: $showingDeleteCloudDataDialog,
            titleVisibility: .visible
        ) {
            Button("Delete from iCloud", role: .destructive) {
                Task { await teardown(deleteCloudData: true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes your tokens from iCloud and your other devices — including data saved by earlier versions of Autheris — then turns sync off. Tokens on this device are kept.")
        }
        .alert(
            "iCloud Sync",
            isPresented: Binding(get: { syncErrorMessage != nil }, set: { if !$0 { syncErrorMessage = nil } })
        ) {
            Button("OK", role: .cancel) { syncErrorMessage = nil }
        } message: {
            Text(syncErrorMessage ?? "")
        }
    }

    @ViewBuilder
    private var syncStatusRow: some View {
        HStack(spacing: 10) {
            if dataStore.syncStatus.isBusy {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: dataStore.syncStatus.systemImage)
                    .foregroundStyle(statusTint)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(dataStore.syncStatus.title)
                    .font(.subheadline.weight(.medium))
                if let detail = dataStore.syncStatus.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if dataStore.syncStatus.allowsRetry {
                Button("Retry") {
                    Task { await dataStore.syncNow() }
                }
                .font(.caption.weight(.semibold))
            }
        }
    }

    /// Leaving sync off is the safe outcome if the cloud delete fails, so the
    /// error is surfaced and the toggle stays where it was.
    private func teardown(deleteCloudData: Bool) async {
        do {
            try await dataStore.disableSync(deleteCloudData: deleteCloudData)
            isICloudSyncEnabled = false
        } catch {
            syncErrorMessage = error.localizedDescription
        }
    }
}

#Preview {
    SettingsView(dataStore: OTPDataStore())
}

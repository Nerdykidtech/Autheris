import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataStore: OTPDataStore
    @AppStorage("enablePrivacyBlur") private var enablePrivacyBlur = true
    @AppStorage("hideCodesInAppSwitcher") private var hideCodesInAppSwitcher = true
    @State private var showingDeleteCloudDataConfirmation = false
    @State private var cloudDeleteError: String?
    
    private var appMarketingVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "—"
    }
    
    private var appBuildNumber: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "—"
    }

    private var cloudSyncFooterText: String {
        #if targetEnvironment(simulator)
        return "iCloud Sync requires a physical iPhone or iPad. It cannot be enabled in the Simulator. On a device, sync is off by default; disabling it stops synchronization and leaves existing iCloud data untouched. Delete iCloud Data removes only Autheris records from iCloud; local tokens remain on this device."
        #else
        return "Optional sync uses your private iCloud account. It is off by default. Disabling sync stops synchronization and leaves existing iCloud data untouched. Delete iCloud Data removes only Autheris records from iCloud; local tokens remain on this device."
        #endif
    }
    
    var body: some View {
        NavigationStack {
            List {
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
                    Toggle("Sync with iCloud", isOn: Binding(
                        get: { dataStore.isCloudSyncEnabled },
                        set: { dataStore.setCloudSyncEnabled($0) }
                    ))
                    .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                    #if targetEnvironment(simulator)
                    .disabled(true)
                    #endif

                    HStack {
                        Text("Status")
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(dataStore.syncStatusTitle)
                                .foregroundStyle(.secondary)
                            if let detail = dataStore.syncStatus.detail {
                                Text(detail)
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                                    .multilineTextAlignment(.trailing)
                                    .frame(maxWidth: 220, alignment: .trailing)
                            }
                        }
                    }

                    if dataStore.isCloudSyncEnabled {
                        Button("Retry Sync") {
                            dataStore.retryCloudSync()
                        }
                        .disabled(dataStore.syncStatus == .syncing)
                    }

                    Button("Delete iCloud Data", role: .destructive) {
                        showingDeleteCloudDataConfirmation = true
                    }
                    .disabled(dataStore.syncStatus == .syncing)
                } header: {
                    Text("iCloud Sync")
                } footer: {
                    Text(cloudSyncFooterText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
        .alert("Delete iCloud Data?", isPresented: $showingDeleteCloudDataConfirmation) {
            Button("Delete iCloud Data", role: .destructive) {
                dataStore.deleteCloudSyncData { result in
                    if case .failure(let error) = result {
                        cloudDeleteError = error.localizedDescription
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes Autheris sync records from iCloud. Your tokens and settings on this device will remain unchanged.")
        }
        .alert("Unable to Delete iCloud Data", isPresented: Binding(
            get: { cloudDeleteError != nil },
            set: { if !$0 { cloudDeleteError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(cloudDeleteError ?? "Please try again.")
        }
        .onChange(of: enablePrivacyBlur) { _, _ in
            dataStore.privacySettingsDidChange()
        }
        .onChange(of: hideCodesInAppSwitcher) { _, _ in
            dataStore.privacySettingsDidChange()
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

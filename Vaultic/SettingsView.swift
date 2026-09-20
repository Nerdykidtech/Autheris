import SwiftUI
import MessageUI
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var dataStore: OTPDataStore
    @AppStorage("enablePrivacyBlur") private var enablePrivacyBlur = true
    @AppStorage("hideCodesInAppSwitcher") private var hideCodesInAppSwitcher = true
    @AppStorage(AppLockEnabledKey) private var enableAppLock = false
    @AppStorage("accentTheme") private var accentThemeRaw = ""
    /// Same key `OTPDataStore` owns, so the toggle and the sync engine cannot drift.
    @AppStorage(OTPDataStore.syncEnabledKey) private var isICloudSyncEnabled = false

    @State private var showingTeardownDialog = false
    @State private var showingDeleteCloudDataDialog = false
    @State private var syncErrorMessage: String?

    @State private var showingBackupView = false
    @State private var showingQRCodeView = false
    @State private var showingImporter = false
    @State private var importMessage: (title: String, body: String)?
    @State private var showingChangelog = false
    @State private var showingSupportMail = false
    @State private var supportTo = "autheris@eddington.tech"
    @State private var supportSubject = "Support Request from Autheris User"
    @State private var supportBody = SupportMailData.troubleshootingTemplate()
    @State private var showingSupportError = false
    @State private var supportErrorMessage = ""

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
                    HStack(spacing: 14) {
                        Image("Logo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 54, height: 54)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Autheris")
                                .font(.title3.weight(.semibold))
                            Text("Version \(appMarketingVersion) (\(appBuildNumber))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Toggle("Blur when backgrounded", isOn: $enablePrivacyBlur)
                        .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                    
                    Toggle("Hide codes in app switcher", isOn: $hideCodesInAppSwitcher)
                        .toggleStyle(SwitchToggleStyle(tint: .accentColor))

                    Toggle("Require Face ID / Touch ID", isOn: $enableAppLock)
                        .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                } header: {
                    Text("Privacy")
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("• **Blur when backgrounded**: Automatically blurs the app when you switch to another app or go to the home screen.")
                        Text("• **Hide codes in app switcher**: Shows a privacy screen instead of your OTP codes when using the app switcher.")
                        Text("• **Require Face ID / Touch ID**: Locks Autheris when opened, or when you return after 30 seconds in the background.")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
                }

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
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            Button {
                                accentThemeRaw = ""
                            } label: {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 36, height: 36)
                                    .overlay(
                                        Circle()
                                            .stroke(
                                                accentThemeRaw.isEmpty
                                                    ? Color.primary
                                                    : Color.clear,
                                                lineWidth: 3
                                            )
                                    )
                                    .overlay(
                                        Text("A")
                                            .font(.caption.weight(.bold))
                                            .foregroundColor(.white)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Default")

                            ForEach(AccentTheme.allCases) { theme in
                                Button {
                                    accentThemeRaw = theme.rawValue
                                } label: {
                                    Circle()
                                        .fill(theme.color)
                                        .frame(width: 36, height: 36)
                                        .overlay(
                                            Circle()
                                                .stroke(
                                                    theme.rawValue == accentThemeRaw
                                                        ? Color.primary
                                                        : Color.clear,
                                                    lineWidth: 3
                                                )
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(theme.displayName)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("Choose an accent tint, or use the default Autheris color.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
                
                Section {
                    Button {
                        showingImporter = true
                    } label: {
                        Label("Import from Another App", systemImage: "square.and.arrow.down")
                    }

                    Button {
                        showingBackupView = true
                    } label: {
                        Label("Backup", systemImage: "externaldrive.badge.plus")
                    }
                    
                    Button {
                        showingQRCodeView = true
                    } label: {
                        Label("Transfer via QR Code", systemImage: "qrcode")
                    }
                } header: {
                    Text("Data")
                } footer: {
                    Text("Imports unencrypted Aegis, andOTP, and 2FAS backup files.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }

                Section {
                    Button {
                        showingChangelog = true
                    } label: {
                        Label("Changelog", systemImage: "list.bullet.rectangle")
                    }
                    
                    Button {
                        presentSupportEmail()
                    } label: {
                        Label("Support", systemImage: "envelope")
                    }
                } header: {
                    Text("Help")
                }
                
                Section {
                    LabeledContent("Version", value: appMarketingVersion)
                    LabeledContent("Build", value: appBuildNumber)

                    Link(destination: URL(string: "https://eddington.tech/autheris")!) {
                        LabeledContent("Website", value: "eddington.tech/autheris")
                    }
                } header: {
                    Text("About")
                } footer: {
                    Text("Made by Hunter Eddington")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
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
            .alert(
                "Support Email",
                isPresented: $showingSupportError
            ) {
                Button("OK", role: .cancel) { showingSupportError = false }
            } message: {
                Text(supportErrorMessage)
            }
        }
        .task {
            // Re-check the iCloud account each time Settings opens, so a user who
            // signed in while the app was running sees the toggle enabled.
            await dataStore.refreshSyncAvailability()
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.json, .plainText],
            allowsMultipleSelection: false
        ) { result in
            handleImportedFile(result)
        }
        .alert(
            Text(importMessage?.title ?? "Import"),
            isPresented: Binding(
                get: { importMessage != nil },
                set: { if !$0 { importMessage = nil } }
            ),
            presenting: importMessage
        ) { _ in
            Button("OK") { importMessage = nil }
        } message: { message in
            Text(message.body)
        }
        .sheet(isPresented: $showingBackupView) {
            BackupView(dataStore: dataStore)
        }
        .sheet(isPresented: $showingQRCodeView) {
            if let exportData = dataStore.exportData() {
                QRCodeView(data: exportData, title: "Export Tokens")
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 50))
                        .foregroundColor(.orange)
                    
                    Text("Unable to Generate QR Code")
                        .font(.headline)
                    
                    Text("There was an error preparing your tokens for export.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button("Dismiss") {
                        showingQRCodeView = false
                    }
                    .padding(.top, 20)
                }
                .padding()
            }
        }
        .sheet(isPresented: $showingChangelog) {
            ChangelogView()
        }
        .sheet(isPresented: $showingSupportMail) {
            SupportMailComposer(
                to: supportTo,
                subject: supportSubject,
                body: supportBody
            )
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

    private func handleImportedFile(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let didStartAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let data = try Data(contentsOf: url)
                let tokens = try ExternalImportParser.parse(data: data)
                let existing = dataStore.codes
                let newTokens = tokens.filter { token in
                    !existing.contains { $0.label == token.label && $0.account == token.account }
                }

                guard !newTokens.isEmpty else {
                    importMessage = ("No New Tokens", "All tokens in this file are already in Autheris.")
                    return
                }

                for token in newTokens {
                    dataStore.addCode(token)
                }
                importMessage = (
                    "Import Complete",
                    "Added \(newTokens.count) token\(newTokens.count == 1 ? "" : "s") to Autheris."
                )
            } catch {
                importMessage = ("Import Failed", error.localizedDescription)
            }

        case .failure(let error):
            importMessage = ("Import Failed", error.localizedDescription)
        }
    }

    private func presentSupportEmail() {
        supportTo = "autheris@eddington.tech"
        supportSubject = "Support Request from Autheris User"
        supportBody = SupportMailData.troubleshootingTemplate()

        if MFMailComposeViewController.canSendMail() {
            showingSupportMail = true
            return
        }

        // Fallback: open Mail app via mailto:
        guard let url = SupportMailData.mailtoURL(to: supportTo, subject: supportSubject, body: supportBody) else {
            supportErrorMessage = "Unable to open Mail. Please email \(supportTo) with subject \"\(supportSubject)\"."
            showingSupportError = true
            return
        }

        UIApplication.shared.open(url)
    }
}

private struct SupportMailData {
    let to: String
    let subject: String
    let body: String

    static func troubleshootingTemplate() -> String {
        let device = UIDevice.current

        let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "Unknown"
        let build = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "Unknown"

        let modelIdentifier = Self.modelIdentifier() ?? "Unknown"

        return """
        Hi Autheris Support,

        I need help with:
        - Issue summary:
        - What I expected to happen:
        - What actually happened:
        - Steps to reproduce:

        Error message (if any):
        -

        Troubleshooting tried:
        -

        Device info:
        - Device: \(device.model) (\(modelIdentifier))
        - iOS: \(device.systemVersion)
        - Autheris: \(appVersion) (\(build))

        Thanks!
        """
    }

    static func mailtoURL(to: String, subject: String, body: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = to
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        return components.url
    }

    static func modelIdentifier() -> String? {
        var systemInfo = utsname()
        uname(&systemInfo)

        let mirror = Mirror(reflecting: systemInfo.machine)
        return mirror.children.compactMap { element -> String? in
            guard let value = element.value as? Int8, value != 0 else { return nil }
            return String(UnicodeScalar(UInt8(value)))
        }.joined()
    }
}

private struct SupportMailComposer: UIViewControllerRepresentable {
    let to: String
    let subject: String
    let body: String

    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: { dismiss() })
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients([to])
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        private let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            onFinish()
        }
    }
}

#Preview {
    SettingsView(dataStore: OTPDataStore())
}

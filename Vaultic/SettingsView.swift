import SwiftUI

#if os(iOS)
import MessageUI
import UIKit
#endif

import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    /// Opens the App Store review form for the "Rate Autheris" row. Cross-platform,
    /// so the Mac preferences window uses the same row with no branch.
    @Environment(\.openURL) private var openURL
    @ObservedObject var dataStore: OTPDataStore

    /// How this view is being shown.
    ///
    /// The settings themselves are identical either way; only the container differs.
    /// Defaulted so the existing sheet call sites are unchanged.
    var presentation: Presentation = .sheet

    /// The two containers this screen can be drawn in.
    enum Presentation {
        /// One scrolling list, in a sheet — what iPhone and iPad use.
        case sheet
        /// The same settings distributed across tabs, in the Mac preferences window.
        case preferences
    }
    @AppStorage("enablePrivacyBlur") private var enablePrivacyBlur = true
    @AppStorage("hideCodesInAppSwitcher") private var hideCodesInAppSwitcher = true
    @AppStorage("hideCodesWhenScreenCaptured") private var hideCodesWhenScreenCaptured = true
    @AppStorage(AppLockEnabledKey) private var enableAppLock = false
    /// Same key the logo lookup reads, so the switch and the network request cannot
    /// drift apart.
    @AppStorage(AppPreferences.fetchIssuerLogosKey) private var fetchIssuerLogos = true
    @AppStorage("accentTheme") private var accentThemeRaw = ""
    /// Same key `OTPDataStore` owns, so the toggle and the sync engine cannot drift.
    @AppStorage(OTPDataStore.syncEnabledKey) private var isICloudSyncEnabled = false

    @State private var showingTeardownDialog = false
    @State private var showingDeleteCloudDataDialog = false
    @State private var syncErrorMessage: String?

    @State private var showingBackupView = false
    /// The open transfer sheet and the link it shows.
    ///
    /// The link is built once as the sheet opens rather than on every redraw of
    /// this screen — it encodes and compresses the whole vault. The sheet is
    /// presented *from* this value (`sheet(item:)`), so its first frame always has
    /// the link: presenting from a flag set alongside it let SwiftUI draw the
    /// sheet before the link arrived, and "too large" flashed up first. SwiftUI
    /// sets it back to `nil` when the sheet closes, which drops the link — it
    /// holds every secret.
    @State private var transferSheet: TransferSheet?
    @State private var showingImporter = false
    @State private var importMessage: (title: String, body: String)?
    @State private var showingChangelog = false
    @State private var showingRecentlyDeleted = false
    @State private var showingSupportMail = false
    @State private var supportTo = "support@autheris.app"
    @State private var supportSubject = "Support Request from Autheris User"
    @State private var supportBody = SupportMailData.troubleshootingTemplate()
    @State private var showingSupportError = false
    @State private var showingAppLockUnavailable = false
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

    // `body` is split across four properties, in modifier order, because as
    // one expression it was too long for the compiler to type-check in time
    // (Xcode 26 gives up on it). Nothing here changes what the screen does.
    var body: some View {
        contentWithSheets
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

    /// `contentWithAlerts` with the sheets.
    private var contentWithSheets: some View {
        contentWithAlerts
        .sheet(isPresented: $showingBackupView) {
            BackupView(dataStore: dataStore)
        }
        .sheet(item: $transferSheet) { sheet in
            if let link = sheet.link {
                QRCodeView(link: link, title: "Export Tokens")
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 50))
                        .foregroundColor(.orange)
                    
                    Text("Unable to Generate QR Code")
                        .font(.headline)
                    
                    Text(transferUnavailableReason)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button("Dismiss") {
                        transferSheet = nil
                    }
                    .padding(.top, 20)
                }
                .padding()
            }
        }
        .sheet(isPresented: $showingChangelog) {
            ChangelogView()
        }
        .sheet(isPresented: $showingRecentlyDeleted) {
            RecentlyDeletedView(dataStore: dataStore)
        }
        .sheet(isPresented: $showingSupportMail) {
            SupportMailComposer(
                to: supportTo,
                subject: supportSubject,
                messageBody: supportBody
            )
        }
    }

    /// `trackedContent` with the alerts, the iCloud refresh and the importer.
    private var contentWithAlerts: some View {
        trackedContent
        // Shared by both containers, so it is attached outside the branch: the
        // Help tab can trigger the same support error as the iPhone's Help section.
        .alert(
            "Support Email",
            isPresented: $showingSupportError
        ) {
            Button("OK", role: .cancel) { showingSupportError = false }
        } message: {
            Text(supportErrorMessage)
        }
        .alert("App Lock Unavailable", isPresented: $showingAppLockUnavailable) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("App Lock needs a passcode or password on this device to unlock Autheris. Set one up, then turn App Lock on again.")
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
    }

    /// The screen for this platform, with the change tracking that earns the
    /// review ask.
    private var trackedContent: some View {
        Group {
            #if os(macOS)
            if presentation == .preferences {
                macPreferencesBody
            } else {
                sheetBody
            }
            #else
            sheetBody
            #endif
        }
        // A change to any setting on this screen is what earns the review ask —
        // see `ReviewPrompt.settingsChanged`.
        //
        // `onChange` does not fire for the values already present when the screen
        // appears, so opening Settings is never itself "doing something", and
        // flipping a toggle back and forth counts as the two changes it is.
        //
        // The iCloud sync toggle is deliberately absent from this list: it is a
        // flow with its own dialogs rather than a plain preference, and the app
        // itself can flip it when the account changes — which would be the app
        // counting its own housekeeping as a user action.
        .onChange(of: enablePrivacyBlur) { _, _ in settingsDidChange() }
        .onChange(of: hideCodesInAppSwitcher) { _, _ in settingsDidChange() }
        .onChange(of: hideCodesWhenScreenCaptured) { _, _ in settingsDidChange() }
        .onChange(of: enableAppLock) { _, _ in settingsDidChange() }
        .onChange(of: accentThemeRaw) { _, _ in settingsDidChange() }
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
                guard case .imported(let added, _) = dataStore.addCodes(tokens) else {
                    importMessage = (String(localized: "Codes Unavailable"), OTPDataStore.vaultUnavailableMessage)
                    return
                }

                guard added > 0 else {
                    importMessage = (
                        String(localized: "No New Tokens"),
                        String(localized: "All tokens in this file are already in Autheris.")
                    )
                    return
                }

                importMessage = (
                    String(localized: "Import Complete"),
                    String(localized: "Added \(added) tokens to Autheris.")
                )
            } catch {
                importMessage = (String(localized: "Import Failed"), error.localizedDescription)
            }

        case .failure(let error):
            importMessage = (String(localized: "Import Failed"), error.localizedDescription)
        }
    }

    /// Called by any change to a setting on this screen.
    ///
    /// `ReviewPrompt` owns the rules and records the ask; this only reports that
    /// something changed, which is the one moment that earns an ask.
    private func settingsDidChange() {
        ReviewPrompt.settingsChanged(codeCount: dataStore.codes.count)
    }

    private func presentSupportEmail() {
        supportTo = "support@autheris.app"
        supportSubject = "Support Request from Autheris User"
        supportBody = SupportMailData.troubleshootingTemplate()

        if PlatformApplication.hasInAppMailComposer {
            showingSupportMail = true
            return
        }

        // Fallback: hand the draft to the user's own mail client via mailto:.
        // On the Mac this is the only path, and the better one.
        guard let url = SupportMailData.mailtoURL(to: supportTo, subject: supportSubject, body: supportBody) else {
            supportErrorMessage = String(localized: "Unable to open Mail. Please email \(supportTo) with subject \"\(supportSubject)\".")
            showingSupportError = true
            return
        }

        PlatformApplication.openMail(url)
    }
    // MARK: - Containers

    /// The iOS and iPad container: every section stacked in one scrolling list.
    private var sheetBody: some View {
        NavigationStack {
            List {

                appHeaderSection

                privacySettingsSection

                syncSettingsSection

                appearanceSettingsSection

                dataSettingsSection

                helpSettingsSection

                aboutSettingsSection
            }
            .navigationTitle("Settings")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .platformSheetTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        // Settings is the tallest sheet in the app — several sections, each with a
        // footer — and a macOS sheet carries no size of its own.
        .platformSheetSize(minWidth: 520, minHeight: 640)
    }

    #if os(macOS)
    /// The Mac container: the same settings as a real preferences window.
    ///
    /// The window, its title and its toolbar all come from the `Settings` scene —
    /// macOS turns a `TabView` of `Label` tab items into the standard preferences
    /// toolbar — so this only has to say which sections go where. The iOS app-header
    /// section is deliberately absent: the window title and the version rows say the
    /// same thing, and a logo badge in a preferences pane is a phone idiom.
    private var macPreferencesBody: some View {
        TabView {
            Form {
                appearanceSettingsSection
                aboutSettingsSection
            }
            .formStyle(.grouped)
            .tabItem { Label("General", systemImage: "gearshape") }

            Form {
                privacySettingsSection
            }
            .formStyle(.grouped)
            .tabItem { Label("Privacy", systemImage: "hand.raised") }

            Form {
                syncSettingsSection
            }
            .formStyle(.grouped)
            .tabItem { Label("iCloud", systemImage: "icloud") }

            Form {
                dataSettingsSection
            }
            .formStyle(.grouped)
            .tabItem { Label("Data", systemImage: "externaldrive") }

            Form {
                helpSettingsSection
            }
            .formStyle(.grouped)
            .tabItem { Label("Help", systemImage: "questionmark.circle") }
        }
        .frame(width: 620, height: 520)
    }
    #endif

    // MARK: - Sections
    //
    // Written once and composed by both containers: the iOS/iPad sheet stacks them
    // in a List, and the Mac preferences window distributes them across tabs. Every
    // setting therefore lives in exactly one place.

    @ViewBuilder
    private var appHeaderSection: some View {
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
    }

    @ViewBuilder
    private var privacySettingsSection: some View {
        Section {
            Toggle("Blur when backgrounded", isOn: $enablePrivacyBlur)
                .platformAccentToggle()
            
            Toggle("Hide codes in app switcher", isOn: $hideCodesInAppSwitcher)
                .platformAccentToggle()
    
            Toggle("Hide codes while recording or mirroring", isOn: $hideCodesWhenScreenCaptured)
                .platformAccentToggle()
    
            Toggle(appLockToggleLabel, isOn: appLockToggleBinding)
                .platformAccentToggle()

            // The one switch here that reaches the network. It sits with the others
            // because that is what it is — a privacy decision — and the footer says
            // exactly what it does rather than leaving it to the label.
            Toggle("Fetch service logos", isOn: $fetchIssuerLogos)
                .platformAccentToggle()
        } header: {
            Text("Privacy")
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                #if os(macOS)
                // A Mac preferences window is narrower and its tab is short, so the
                // iPhone's per-switch list reads as a wall of text. The switch labels
                // carry the meaning already; this says what they add up to.
                Text("Codes are hidden whenever Autheris isn't the frontmost app, and while the screen is being recorded or mirrored. App Lock re-locks 30 seconds after you leave.")
                #else
                Text("• **Blur when backgrounded**: Automatically blurs the app when you switch to another app or go to the home screen.")
                Text("• **Hide codes in app switcher**: Shows a privacy screen instead of your OTP codes when using the app switcher.")
                Text("• **Hide codes while recording or mirroring**: Shows a privacy screen while the screen is being recorded or sent to another display.")
                Text("• **Require Face ID / Touch ID**: Locks Autheris when opened, or when you return after 30 seconds in the background.")
                #endif
                Text("**Fetch service logos** looks each service's icon up by name at logo.dev, which tells that logo service which brands you have. Turned off, nothing new is looked up and any service without a saved icon shows its letter.")
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.top, 4)
        }
    }

    /// Turning App Lock on takes effect straight away; turning it off asks for
    /// authentication first, so a phone unlocked moments ago can't be stripped of it.
    ///
    /// It only turns on when the device can authenticate its owner. Without a
    /// passcode the lock screen would have nothing to ask for.
    private var appLockToggleBinding: Binding<Bool> {
        Binding(
            get: { enableAppLock },
            set: { newValue in
                guard !newValue else {
                    if AppLockManager.canLock() {
                        enableAppLock = true
                    } else {
                        showingAppLockUnavailable = true
                    }
                    return
                }
                Task {
                    if await AppLockManager.reauthenticate(
                        reason: String(localized: "Authenticate to turn off App Lock.")
                    ) {
                        enableAppLock = false
                    }
                }
            }
        )
    }

    /// Why there is no transfer QR code: the codes can't be read, or there are
    /// more than one QR code holds even in the compact format.
    private var transferUnavailableReason: String {
        dataStore.isVaultLoaded
            ? String(localized: "This export is too large for a single QR code. Use Backup from the menu to transfer your tokens as a file instead.")
            : OTPDataStore.vaultUnavailableMessage
    }

    /// The App Lock switch's label.
    ///
    /// macOS has no Face ID, and on a Mac without Touch ID the system falls back to
    /// the login password — so naming Face ID there would be wrong twice over.
    private var appLockToggleLabel: String {
        #if os(macOS)
        return "Require Touch ID or password"
        #else
        return "Require Face ID / Touch ID"
        #endif
    }

    @ViewBuilder
    private var syncSettingsSection: some View {
        Section {
            Toggle("Sync with iCloud", isOn: syncToggleBinding)
                .platformAccentToggle()
    
            syncStatusRow
    
            if !dataStore.isSyncAvailable && !isICloudSyncEnabled
                && !dataStore.syncStatus.isConfigurationFailure {
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
    }

    @ViewBuilder
    private var appearanceSettingsSection: some View {
        Section {
            PlatformSwatchRow {
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
                            // A colour-swatch glyph, not a word: `verbatim` keeps
                            // it out of the catalog.
                            Text(verbatim: "A")
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
        } header: {
            Text("Appearance")
        } footer: {
            Text("Choose an accent tint, or use the default Autheris color.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var dataSettingsSection: some View {
        Section {
            Button {
                showingImporter = true
            } label: {
                actionRowLabel("Import from Another App", systemImage: "square.and.arrow.down")
            }
            .platformPlainButton()
    
            Button {
                Task {
                    if await AppLockManager.reauthenticate(
                        reason: String(localized: "Authenticate to back up your tokens.")
                    ) {
                        showingBackupView = true
                    }
                }
            } label: {
                actionRowLabel("Backup", systemImage: "externaldrive.badge.plus")
            }
            .platformPlainButton()
            
            Button {
                Task {
                    if await AppLockManager.reauthenticate(
                        reason: String(localized: "Authenticate to export your tokens.")
                    ) {
                        transferSheet = TransferSheet(link: dataStore.transferLink())
                    }
                }
            } label: {
                actionRowLabel("Transfer via QR Code", systemImage: "qrcode")
            }
            .platformPlainButton()
    
            #if os(macOS)
            // A `NavigationLink` needs a navigation stack to push into. The Mac
            // Data tab is a plain form in the preferences window — pushing would
            // replace the tab's content and leave the tab bar stranded above a back
            // button — so it opens the same screen as a sheet instead.
            Button {
                showingRecentlyDeleted = true
            } label: {
                recentlyDeletedRowLabel
            }
            .platformPlainButton()
            #else
            NavigationLink {
                RecentlyDeletedView(dataStore: dataStore)
            } label: {
                recentlyDeletedRowLabel
            }
            #endif
        } header: {
            Text("Data")
        } footer: {
            Text("Imports unencrypted Aegis, andOTP, and 2FAS backup files. Deleted codes stay recoverable on this device for \(TrashBin.retentionDays) days.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 4)
        }
    }

    /// An action row in the Data and Help sections.
    ///
    /// iOS already draws a `Button` in a `List` as a plain row. macOS draws its
    /// default bordered chrome instead, and around a `Label` that wraps the icon and
    /// the title in *separate* grey capsules — so a row read as two grey pills
    /// rather than a setting. The fix is `.platformPlainButton()` at the call site;
    /// this supplies the trailing chevron those rows need in exchange, because a
    /// chrome-less row otherwise gives no hint that it opens anything.
    ///
    /// The title is a `LocalizedStringKey` and not a `String`: a `String` parameter
    /// carries a literal straight to `Label` without a lookup, which is how these
    /// five rows came to be the only English left on an otherwise translated Mac
    /// Settings window.
    @ViewBuilder
    private func actionRowLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
        #if os(macOS)
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            actionRowChevron
        }
        // Without this the row only responds to a click directly on its icon or text:
        // a plain-styled macOS button is hittable only where its label draws, and the
        // `Spacer` draws nothing.
        .platformActionRowHitArea()
        #else
        Label(title, systemImage: systemImage)
        #endif
    }

    #if os(macOS)
    private var actionRowChevron: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tertiary)
    }
    #endif

    /// The Recently Deleted row, shared by the `Button` and `NavigationLink` forms.
    private var recentlyDeletedRowLabel: some View {
        HStack {
            Label("Recently Deleted", systemImage: "trash")
            Spacer()
            if !dataStore.trash.isEmpty {
                // A count badge: `verbatim` keeps a bare "%lld" out of the catalog.
                Text(verbatim: "\(dataStore.trash.count)")
                    .foregroundColor(.secondary)
            }
            #if os(macOS)
            actionRowChevron
            #endif
        }
        .platformActionRowHitArea()
    }

    @ViewBuilder
    private var helpSettingsSection: some View {
        Section {
            Button {
                showingChangelog = true
            } label: {
                actionRowLabel("Changelog", systemImage: "list.bullet.rectangle")
            }
            .platformPlainButton()
            
            Button {
                presentSupportEmail()
            } label: {
                actionRowLabel("Support", systemImage: "envelope")
            }
            .platformPlainButton()

            // The only review control the user owns. Apple's guidance is explicit
            // that the review *prompt* must not be raised from a button tap — it
            // may present nothing, and it does nothing at all in TestFlight — so a
            // settings screen gets the write-review link instead, which opens the
            // App Store app on the review form every time.
            Button {
                if let url = ReviewPrompt.writeReviewURL { openURL(url) }
            } label: {
                actionRowLabel("Rate Autheris", systemImage: "star")
            }
            .platformPlainButton()
        } header: {
            Text("Help")
        }
    }

    @ViewBuilder
    private var aboutSettingsSection: some View {
        Section {
            LabeledContent("Version", value: appMarketingVersion)
            LabeledContent("Build", value: appBuildNumber)
    
            Link(destination: URL(string: "https://autheris.app")!) {
                LabeledContent("Website", value: "autheris.app")
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

}

private struct SupportMailData {
    let to: String
    let subject: String
    let body: String

    static func troubleshootingTemplate() -> String {
        let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "Unknown"
        let build = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "Unknown"

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
        - Device: \(PlatformApplication.deviceDescription)
        - \(PlatformApplication.osName): \(PlatformApplication.osVersion)
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
}

/// The support-mail draft, as a sheet.
///
/// iOS presents `MFMailComposeViewController`, which is the only place a draft
/// can be composed and sent without leaving the app. macOS has no such
/// controller, so this renders nothing there — and nothing needs it to, because
/// `PlatformApplication.hasInAppMailComposer` is `false` and the caller takes the
/// `mailto:` route instead. The sheet is kept rather than branched at the call
/// site so the view hierarchy stays the same shape on both platforms.
private struct SupportMailComposer: View {
    let to: String
    let subject: String
    /// Named `messageBody` rather than `body`: `body` is already the `View`
    /// requirement on this struct.
    let messageBody: String

    var body: some View {
        #if os(iOS)
        MailComposerRepresentable(to: to, subject: subject, messageBody: messageBody)
        #else
        EmptyView()
        #endif
    }
}

#if os(iOS)
private struct MailComposerRepresentable: UIViewControllerRepresentable {
    let to: String
    let subject: String
    let messageBody: String

    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: { dismiss() })
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients([to])
        vc.setSubject(subject)
        vc.setMessageBody(messageBody, isHTML: false)
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
#endif

#Preview {
    SettingsView(dataStore: OTPDataStore())
}

/// What the transfer sheet shows: the link, or `nil` when there is none to show
/// (see `OTPDataStore.transferLink()`). A fresh id each time, so each opening
/// is its own presentation.
private struct TransferSheet: Identifiable {
    let id = UUID()
    let link: String?
}

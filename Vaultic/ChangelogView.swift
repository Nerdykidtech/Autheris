import SwiftUI

struct ChangelogView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var expandedReleaseId: String? = ChangelogRelease.catalog.first?.id
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(ChangelogRelease.catalog) { release in
                        ChangelogVersionRow(
                            release: release,
                            isExpanded: expandedReleaseId == release.id,
                            onToggle: {
                                withAnimation(.easeInOut(duration: 0.22)) {
                                    if expandedReleaseId == release.id {
                                        expandedReleaseId = nil
                                    } else {
                                        expandedReleaseId = release.id
                                    }
                                }
                            }
                        )
                    }
                } footer: {
                    Text("Tap a version to show or hide release notes. Newest first.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .navigationTitle("Changelog")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .platformSheetTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .platformSheetDetents(dragIndicator: true)
            .platformSheetSize()
    }
}

// MARK: - Data

struct ChangelogRelease: Identifiable, Sendable {
    let id: String
    let version: String
    let date: String
    let changes: [String]
    
    static let catalog: [ChangelogRelease] = [
        ChangelogRelease(
            id: "2.2",
            version: "2.2",
            date: "September 2026",
            changes: [
                "Autheris now runs on the Mac — a real Mac app rather than a phone app stretched across the desktop. Your codes, sync and settings are unchanged: add an account on your iPhone and it is there on your Mac.",
                "Settings on the Mac is a proper preferences window. Open it from the gear or with ⌘, and find everything grouped into General, Privacy, iCloud, Data and Help.",
                "Scan QR codes with your Mac's built-in or attached camera, including Google Authenticator transfer codes.",
                "App Lock works on the Mac: Touch ID where your Mac has it, and your login password where it does not.",
                "Codes are hidden from screen sharing and recording, so a call or a demo cannot put your codes on someone else's screen.",
                "The small things a Mac expects: switch controls use the system's own blue, the accent colours sit in a row rather than a scroller, lists reorder by dragging a row directly, search lives in the window toolbar, and copied codes are marked as concealed so they do not travel to your other devices through Universal Clipboard.",
                "Support on the Mac opens your own mail app with the troubleshooting details already filled in.",
                "Fixed a set of Mac teething problems: some sheets opened as an empty box, several could not be closed at all, Recently Deleted had no way back, and the buttons in Settings did not respond everywhere they looked like they should.",
                "Fixed a crash when starting the Mac's QR scanner.",
                "Fixed a startup crash in builds where iCloud is unavailable — the app now opens normally and explains that sync is unavailable, instead of refusing to start."
            ]
        ),
        ChangelogRelease(
            id: "2.1",
            version: "2.1",
            date: "September 2026",
            changes: [
                "Autheris now runs on iPad as well as iPhone. Your codes, sync, and settings are unchanged — the app is simply built for the larger screen too.",
                "The token list is a grid on iPad — two codes per row, with a larger code and countdown on each card — instead of a single column stretched across the screen.",
                "Tap Edit and drag a card by its grabber handle — the same control as on iPhone. The other codes move out of the way as you carry one past them, and it settles where you let go.",
                "Onboarding, the import summary, and Settings are sized for the larger screen rather than stretched across it."
            ]
        ),
        ChangelogRelease(
            id: "2.0",
            version: "2.0",
            date: "September 2026",
            changes: [
                "Redesigned home screen: cleaner token cards with larger issuer icons, glanceable countdowns, and native search.",
                "Reorganized navigation: Settings is a full-screen hub for Privacy, iCloud Sync, Appearance, Data, Help, and About.",
                "Add Token and Edit Token are rebuilt as native forms, with PhotosPicker for QR screenshots and standard alerts. Account is optional, and the code on the Edit screen updates live as you change its settings.",
                "SHA-256 and SHA-512 can now be selected when adding or editing a code, not just SHA-1 — some services (myGov, for example) require SHA-256 and would previously reject every code.",
                "App Lock with Face ID / Touch ID — locks on launch and after 30 seconds in the background, with passcode fallback.",
                "Codes are covered while the screen is being recorded or mirrored to another display, alongside the existing app-switcher and background protection.",
                "Tokens, preferences, and pending deletions now live in the Keychain, so your accounts and settings survive reinstalling the app — and a code you deleted cannot come back afterwards.",
                "Password-encrypted backups: AES-GCM files protected by your own password, alongside the existing plain backup option.",
                "Import from more authenticators: unencrypted Aegis, andOTP, and 2FAS backup files.",
                "Copied codes and setup keys automatically clear from the clipboard after 60 seconds.",
                "Pin the codes you use most to the top of the list, and drag the rest into whatever order suits you.",
                "A deleted code is kept in “Recently Deleted” for 7 days, so a wrong tap is recoverable — restore it, or remove it for good straight away.",
                "Optional accent tints keep the default Autheris look unless you pick a theme.",
                "Fresh onboarding that matches the new design, with Reduce Motion support.",
                "The app is now named Autheris on your home screen, matching the name it uses in the App Store.",
                "Fixed a crash a malformed setup link or backup file could trigger, by validating a code's digit count and refresh period rather than trusting them.",
                "Polish pass: dark-mode contrast fixes, Dynamic Type, and accessibility improvements."
            ]
        ),
        ChangelogRelease(
            id: "1.3",
            version: "1.3",
            date: "September 2026",
            changes: [
                "Optional iCloud Sync in Settings — off by default, and iCloud is never contacted until you turn it on. Tokens sync across your own devices through your private iCloud database.",
                "Your secrets stay protected: label, account, secret, and ring color are end-to-end encrypted by CloudKit and are never stored in a readable form.",
                "Adds, edits, and deletes sync automatically. The newest edit wins, and deletes use tombstones so a token deleted on one device can't reappear from another device that was offline.",
                "Settings shows live sync status — Synced with “last updated,” Syncing, paused when offline, or Sign in to iCloud — and turning sync off asks whether to keep tokens on this device or delete them from iCloud first."
            ]
        ),
        ChangelogRelease(
            id: "1.2",
            version: "1.2",
            date: "September 2026",
            changes: [
                "Long-press a token and choose “View Secret” to see its setup key. The key is masked by default — tap it (or use the eye icon) to reveal, with Copy to grab it quickly.",
                "Secret edits happen in the same sheet and require an explicit Save; changes are validated as a Base32 key first, and canceling with unsaved edits asks before discarding.",
                "The Edit sheet keeps its original scope — service name, account, and ring color — with the same unsaved-changes guard."
            ]
        ),
        ChangelogRelease(
            id: "1.1",
            version: "1.1",
            date: "March 2026",
            changes: [
                "QR export uses compact JSON (no extra whitespace) and QR error-correction level L so more accounts fit in a single code.",
                "If the encoded URL still exceeds what a QR code can hold, the app stops loading indefinitely and explains the limit, with guidance to use Backup for file-based transfer.",
                "Countdown ring color can be customized per token in Edit: use the system color picker, or “Use service default” to follow the automatic issuer color.",
                "Settings shows marketing version and build from the bundle. Release notes live here under Changelog in the main menu."
            ]
        ),
        ChangelogRelease(
            id: "1.0",
            version: "1.0",
            date: "Initial release",
            changes: [
                "First release of Autheris: TOTP codes, search, backup and restore, QR import, privacy blur and app-switcher hiding, and issuer-aware visuals."
            ]
        )
    ]
}

// MARK: - Row

struct ChangelogVersionRow: View {
    let release: ChangelogRelease
    let isExpanded: Bool
    let onToggle: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Version \(release.version)")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(release.date)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    
                    Spacer(minLength: 8)
                    
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Version \(release.version), \(release.date)")
            .accessibilityHint(isExpanded ? "Collapse release notes" : "Expand release notes")
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(release.changes.enumerated()), id: \.offset) { index, line in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(index + 1)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.tertiary)
                                .frame(width: 18, alignment: .trailing)
                                .padding(.top, 2)
                            
                            Text(line)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 4)
                .padding(.leading, 2)
            }
        }
        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
    }
}

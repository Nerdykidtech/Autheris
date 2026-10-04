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
            id: "3.0",
            version: "3.0",
            date: "October 2026",
            changes: [
                "Other apps can now offer an Add to Autheris button. When you turn on two-factor authentication in an app that has one, a single tap opens Autheris with the new code, instead of a QR code you can't scan from the same phone.",
                "As with every link since 2.8, Autheris shows you the code and waits for you to tap Import. Nothing is added unless you do, and if App Lock is on it waits until you unlock.",
                "Blur when backgrounded, Hide codes in app switcher, and Hide codes while recording or mirroring are on again. They could switch themselves off on the second launch if you had never changed them, so 3.0 turns them back on once. If you had turned one off on purpose, turn it off again in Settings and it will stay off.",
                "Your codes can no longer be lost when iCloud sync wakes Autheris while your iPhone is locked. It now waits until you unlock before it loads, saves, syncs or updates Apple Watch.",
                "Restoring an encrypted backup now asks before it replaces your codes, and codes it replaces go to Recently Deleted instead of disappearing.",
                "Scanning a transfer or Google Authenticator export QR code now shows what it would add, and nothing is added until you tap Import.",
                "App Lock can no longer be turned on without a device passcode, which could leave Autheris stuck on the lock screen.",
                "If Autheris can't read your codes from the Keychain, it now says so and leaves them untouched instead of risking an empty list replacing them. If this version can't read them at all, you can set them aside and start over.",
                "With iCloud sync on, a device that was behind no longer overwrites a newer change from another device.",
                "Two codes with the same name can no longer lose one of them, and renaming a code to a name another code has is refused.",
                "Setup links that name only the account, and imports from 2FAS, now keep the account, so a second account at the same service can be added.",
                "Adding a code that's already on your device now says so instead of closing as if it worked.",
                "The Transfer QR Code now holds typically 50 to 130 codes instead of 8. A bigger transfer needs Autheris 3.0 on the other device.",
                "Encrypted backups no longer freeze the app while they're created or opened.",
                "Your codes, iCloud sync and settings are exactly where you left them, apart from the three privacy switches above."
            ]
        ),
        ChangelogRelease(
            id: "2.8",
            version: "2.8",
            date: "October 2026",
            changes: [
                "Links that add codes — from another app, a web page, or a Google Authenticator export — now always show you what they would add, and nothing is added until you tap Import. They used to add codes the moment they arrived, which could put entries in your list that you never asked for.",
                "A link that arrives while Autheris is locked now waits until you unlock it, instead of going through behind the lock screen.",
                "With App Lock on, Autheris asks for Face ID, Touch ID or your passcode again before turning App Lock off, opening Backup, transferring codes by QR code, or showing a setup key.",
                "Backups now stay on this device instead of being copied into iCloud and computer backups, and encrypted backups are much harder to crack. A new encrypted backup needs a password of at least 10 characters.",
                "Restoring a backup picked from Files now works reliably, brings back codes you had deleted since it was made, and tells you when it's done.",
                "With iCloud sync on, deleting a code now removes it from your other devices too, and a change made while a sync is running is uploaded as soon as it finishes.",
                "Imports now report how many codes were really added.",
                "On the Mac, the Settings window is locked while Autheris is, and App Lock re-locks 30 seconds after you switch to another app.",
                "Thanks to NotAFlightRisk for finding and responsibly reporting the link issue.",
                "Your codes, iCloud sync and settings are exactly where you left them."
            ]
        ),
        ChangelogRelease(
            id: "2.7",
            version: "2.7",
            date: "October 2026",
            changes: [
                "This release changes how Autheris looks in the App Store, not how it works — the listing now carries a new set of screenshots for iPhone, iPad, Mac and Apple Watch.",
                "Nothing else changed: no new settings, no new permissions, and no new network requests.",
                "Your codes, iCloud sync and settings are exactly where you left them."
            ]
        ),
        ChangelogRelease(
            id: "2.6",
            version: "2.6",
            date: "September 2026",
            changes: [
                "Autheris can now generate counter-based codes as well as the time-based ones it has always used. Some services hand you a counter instead of a code that changes on a timer: that code stays the same until you ask for the next one, and its card shows which counter it is on, with a Next button beside it.",
                "Scanning one of those codes used to add it as a time-based one, so its codes were always rejected and nothing on screen explained why. It now adds the right kind of code.",
                "Importing got the same fix. Counter-based accounts in a Google Authenticator export used to be skipped without a word, and Aegis and andOTP backups now bring their counters across too.",
                "The Apple Watch shows counter-based codes as well, with the counter where the countdown would be. The watch stays read-only, so you advance the counter on your iPhone.",
                "Settings → Privacy has a new switch, Fetch service logos. It controls the one request Autheris can make over the network — looking a service's icon up by name at logo.dev, which tells that logo service which brands you have. With it off, nothing is looked up and every service falls back to its letter.",
                "Autheris now speaks Spanish, French, German, Japanese, Simplified Chinese and Brazilian Portuguese — the same six languages the App Store listing has been translated into — including the camera and Face ID permission prompts and the Apple Watch app. If your device is set to one of them, the app opens in it.",
                "Your codes, iCloud sync and settings are exactly where you left them."
            ]
        ),
        ChangelogRelease(
            id: "2.5",
            version: "2.5",
            date: "September 2026",
            changes: [
                "Autheris now speaks Spanish, French, German, Japanese, Simplified Chinese and Brazilian Portuguese — the same six languages the App Store listing has been translated into since 2.4. If your device is set to one of them, the app opens in it.",
                "The Apple Watch app speaks them too, so the codes on your wrist read in the same language as the ones in your pocket.",
                "The camera and Face ID permission prompts are translated as well. Those come from the system rather than the app, so they were the last English a translated app still showed.",
                "Your codes, iCloud sync and settings are exactly where you left them."
            ]
        ),
        ChangelogRelease(
            id: "2.4",
            version: "2.4",
            date: "September 2026",
            changes: [
                "Autheris now has an Apple Watch app. Your codes are on your wrist — one at a time, a swipe or a turn of the Digital Crown apart, each with its own countdown.",
                "The watch app is deliberately read-only: there is no copy, no editing and no settings on the watch. Adding, changing and deleting codes still happens on your iPhone, and the iPhone sends the list over. Installing the watch app is what turns that on — if you never install it, nothing is sent.",
                "Codes are generated on the watch itself, so they keep counting down with your iPhone out of reach or switched off. A code you add on your iPhone appears on the watch within seconds, and a code you delete disappears just as quickly.",
                "The watch is a viewer, not a second vault to keep in step. Its copy of your codes gets the same protection the iPhone's does, and it is never edited there.",
                "Your codes, iCloud sync and settings are exactly where you left them."
            ]
        ),
        ChangelogRelease(
            id: "2.3",
            version: "2.3",
            date: "September 2026",
            changes: [
                "Autheris can now ask for an App Store rating. Settings has a Rate Autheris row under Help for whenever you want to leave one, and the app will ask by itself once, after you change a setting — never on launch, and at most once per version.",
                "On the Mac, the app is now named Autheris everywhere — it previously installed as Vaultic, so the Dock, the menu bar and your Applications folder called it something else. They now match the name the app already uses in the App Store.",
                "Your codes, iCloud sync and settings are exactly where you left them.",
                "If an older copy named Vaultic is still in your Applications folder, you can move it to the Trash — Autheris is the app from here on."
            ]
        ),
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

    /// Typed explicitly: a ternary of two literals infers as `String`, which
    /// renders verbatim and is never looked up.
    private var releaseNotesHint: LocalizedStringKey {
        isExpanded ? "Collapse release notes" : "Expand release notes"
    }
    
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
            .accessibilityHint(releaseNotesHint)
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(release.changes.enumerated()), id: \.offset) { index, line in
                        HStack(alignment: .top, spacing: 10) {
                            // A list position, not prose: `verbatim` keeps it out
                            // of the catalog instead of adding a "%lld" key.
                            Text(verbatim: "\(index + 1)")
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

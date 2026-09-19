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

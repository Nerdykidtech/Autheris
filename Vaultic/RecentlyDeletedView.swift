import SwiftUI

/// The "Recently Deleted" list, reached from **Settings → Data → Recently Deleted**.
///
/// The retention window and the restore conflict rule live in `TrashBin`; this
/// view only presents them. Everything here is local to the device — the trash
/// does not sync, and deleting a code still propagates immediately.
struct RecentlyDeletedView: View {
    @ObservedObject var dataStore: OTPDataStore

    @State private var showingDeleteAllConfirmation = false
    @State private var message: (title: String, body: String)?

    private var entries: [TrashBin.Entry] {
        TrashBin.newestFirst(dataStore.trash)
    }

    var body: some View {
        Group {
            if entries.isEmpty {
                emptyState
            } else {
                List {
                    Section {
                        ForEach(entries) { entry in
                            row(entry)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        dataStore.deletePermanently(entry)
                                    } label: {
                                        Label("Delete Now", systemImage: "trash.slash")
                                    }
                                }
                        }
                    } footer: {
                        Text("Codes are kept on this device for \(TrashBin.retentionDays) days, then removed for good. Deleting a code still removes it from your other devices straight away.")
                            .font(.caption)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Recently Deleted")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !entries.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Delete All", role: .destructive) {
                        showingDeleteAllConfirmation = true
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete All?",
            isPresented: $showingDeleteAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete \(entries.count) Code\(entries.count == 1 ? "" : "s")", role: .destructive) {
                dataStore.emptyTrash()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("These codes will be permanently removed from this device. This cannot be undone.")
        }
        .alert(
            Text(message?.title ?? "Recently Deleted"),
            isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            ),
            presenting: message
        ) { _ in
            Button("OK") { message = nil }
        } message: { result in
            Text(result.body)
        }
        .onAppear {
            // An entry can outlive its window while the app stays running, so
            // re-check whenever the list is opened.
            dataStore.purgeExpiredTrash()
        }
    }

    // MARK: - Rows

    private func row(_ entry: TrashBin.Entry) -> some View {
        HStack(spacing: 12) {
            IssuerIconView(branding: IssuerBranding.forLabel(entry.code.label), size: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.code.label)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                if !entry.code.account.isEmpty {
                    Text(entry.code.account)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Text(timeLeftText(for: entry))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 8)

            Button("Restore") {
                restore(entry)
            }
            .font(.footnote.weight(.semibold))
            .buttonStyle(.bordered)
            .tint(.accentColor)
        }
        .padding(.vertical, 2)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "trash")
                .font(.system(size: 40))
                .foregroundColor(.accentColor)
                .opacity(0.5)

            Text("Nothing Deleted")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Codes you delete are kept here for \(TrashBin.retentionDays) days in case you change your mind.")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func restore(_ entry: TrashBin.Entry) {
        guard case .collides = dataStore.restoreFromTrash(entry) else { return }

        message = (
            "Can't Restore",
            "A code called \"\(entry.code.label)\" with the same account already exists. Delete that one first, then restore this."
        )
    }

    private func timeLeftText(for entry: TrashBin.Entry) -> String {
        let days = Calendar.current
            .dateComponents([.day], from: Date(), to: entry.expiry())
            .day ?? 0

        switch days {
        case ..<1: return "Less than a day left"
        case 1: return "1 day left"
        default: return "\(days) days left"
        }
    }
}

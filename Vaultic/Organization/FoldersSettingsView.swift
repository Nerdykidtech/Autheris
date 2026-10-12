import SwiftUI

/// The Settings page where folders are turned on and kept.
///
/// Off by default. Turned on, it lists the folders, each with the number of tokens
/// in it, and lets the user add, rename and delete them. The sheet and the
/// confirmation hang on this list rather than on a row, so an edit does not close them.
struct FoldersSettingsView: View {
    @Environment(TokenOrganizationStore.self) private var store
    @AppStorage(TokenOrganizationStore.enabledKey) private var isEnabled = false

    /// The name sheet, or `nil` when it is closed.
    @State private var editing: NameEdit?
    /// The folder waiting on the delete confirmation, or `nil`.
    @State private var deleting: ItemToDelete?

    /// One opening of the name sheet. A new id each time, so the sheet always starts
    /// from the folder it was opened for.
    private struct NameEdit: Identifiable {
        let id = UUID()
        /// `nil` to add a new folder; the folder's id to change it.
        let folderID: UUID?
        let initialName: String
        let initialColor: FolderColor?
    }

    private struct ItemToDelete: Identifiable {
        let id = UUID()
        let folderID: UUID
    }

    var body: some View {
        List {
            Section {
                Toggle("Folders", isOn: $isEnabled)
            } footer: {
                Text("Sort your tokens into folders. With Sync with iCloud on, folders and the tokens in them sync to your other devices through your private iCloud database. They are not part of backups, Transfer QR codes or the Apple Watch.")
                    .settingsFooterStyle()
            }

            if isEnabled {
                folderSection
            }
        }
        .navigationTitle("Folders")
        .inlineNavigationTitle()
        .sheet(item: $editing) { edit in
            OrganizationNameSheet(title: edit.folderID == nil ? "New Folder" : "Edit Folder",
                                  initialName: edit.initialName,
                                  initialColor: edit.initialColor) { name, color in
                save(name, color, for: edit)
            }
        }
        .confirmationDialog(
            "Delete Folder?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let item = deleting else { return }
                store.update { $0.deleteFolder(item.folderID) }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Its tokens stay in your list, just not in this folder.")
        }
    }

    // MARK: - Sections

    private var folderSection: some View {
        let folders = store.organization.folders
        return Section {
            ForEach(folders) { folder in
                Button {
                    editing = NameEdit(folderID: folder.id, initialName: folder.name, initialColor: folder.color)
                } label: {
                    LabeledContent {
                        Text(store.organization.count(inFolder: folder.id), format: .number)
                            .foregroundStyle(.secondary)
                    } label: {
                        Label {
                            Text(folder.name)
                                .foregroundStyle(.primary)
                        } icon: {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(folder.color?.color ?? .secondary)
                        }
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button("Delete", role: .destructive) {
                        deleting = ItemToDelete(folderID: folder.id)
                    }
                }
            }

            Button {
                editing = NameEdit(folderID: nil, initialName: "", initialColor: nil)
            } label: {
                Label("Add Folder", systemImage: "plus.circle.fill")
            }
        } header: {
            Text("Folders")
        } footer: {
            if folders.isEmpty {
                Text("Folders hold a token in one place, such as Work or Banking.")
                    .settingsFooterStyle()
            }
        }
    }

    /// Saves a folder's name and colour, and reports whether the name was kept. A
    /// refused name changes nothing, colour included.
    private func save(_ name: String, _ color: FolderColor?, for edit: NameEdit) -> Bool {
        var kept = false
        store.update { organization in
            if let id = edit.folderID {
                kept = organization.renameFolder(id, to: name)
                if kept {
                    organization.setFolderColor(color, for: id)
                }
            } else {
                kept = organization.addFolder(named: name, color: color) != nil
            }
        }
        return kept
    }
}

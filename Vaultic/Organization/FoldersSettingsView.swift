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

    /// One opening of the name sheet. A new id each time, so the sheet always starts
    /// from the folder it was opened for.
    private struct NameEdit: Identifiable {
        let id = UUID()
        /// `nil` to add a new folder; the folder's id to change it.
        let folderID: UUID?
        let initialName: String
        let initialColor: FolderColor?
    }

    var body: some View {
        Group {
            #if os(macOS)
            // The Mac's preference tabs are grouped forms with section headers.
            Form {
                pageContent
            }
            .formStyle(.grouped)
            #else
            // The iPhone and iPad pages are grouped lists, like the rest of Settings.
            List {
                pageContent
            }
            #endif
        }
        .navigationTitle("Folders")
        .inlineNavigationTitle()
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .platformTrailing) {
                EditButton()
            }
        }
        #endif
        .sheet(item: $editing) { edit in
            OrganizationNameSheet(
                title: edit.folderID == nil ? "New Folder" : "Edit Folder",
                initialName: edit.initialName,
                initialColor: edit.initialColor,
                onDelete: edit.folderID.map { id in { store.update { $0.deleteFolder(id) } } }
            ) { name, color in
                save(name, color, for: edit)
            }
        }
    }

    @ViewBuilder
    private var pageContent: some View {
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

    // MARK: - Sections

    private var folderSection: some View {
        let folders = store.organization.folders
        return Section {
            if folders.isEmpty {
                ContentUnavailableView {
                    Label("No Folders Yet", systemImage: "folder.badge.plus")
                } description: {
                    Text("Create a folder to sort your tokens.")
                }
                .listRowBackground(Color.clear)
            }

            ForEach(folders) { folder in
                folderRow(folder)
            }
            // Reordering: Edit mode on iPhone and iPad, a drag on the Mac. The order is
            // also the order of the chips on Home. A folder is deleted from its sheet.
            .onMove { source, destination in
                store.update { $0.moveFolders(from: source, to: destination) }
            }

            #if os(iOS)
            // Styled like the other action rows in Settings: the title in the primary
            // colour, with only the icon tinted.
            Button(action: addFolder) {
                Label {
                    Text("Add Folder")
                        .foregroundStyle(Color.primary)
                } icon: {
                    Image(systemName: "plus.circle.fill")
                }
            }
            #endif
        } footer: {
            #if os(macOS)
            // A Mac list puts its add button under the list, trailing, as System
            // Settings does, rather than as a row inside it.
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if !folders.isEmpty {
                    Text("Click a folder to rename it, change its colour or delete it. Drag folders to change their order.")
                        .settingsFooterStyle()
                }
                Spacer(minLength: 0)
                Button("Add Folder", action: addFolder)
            }
            #else
            if !folders.isEmpty {
                Text("Tap a folder to rename it, change its colour or delete it. Use Edit to change the order.")
                    .settingsFooterStyle()
            }
            #endif
        }
    }

    /// One folder: its colour tile, its name, and how many tokens it holds.
    ///
    /// A plain row with a tap, not a `Button`: a button-styled row made the card's
    /// rounded corners redraw after a swipe on iPhone.
    private func folderRow(_ folder: OrganizationItem) -> some View {
        LabeledContent {
            Text(store.organization.count(inFolder: folder.id), format: .number)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        } label: {
            HStack(spacing: Self.rowSpacing) {
                SettingsRowIcon(systemImage: "folder.fill", tint: folder.color?.color ?? .gray,
                                size: Self.iconSize)
                Text(folder.name)
                    .foregroundStyle(.primary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            editing = NameEdit(folderID: folder.id, initialName: folder.name, initialColor: folder.color)
        }
        .accessibilityAddTraits(.isButton)
    }

    private func addFolder() {
        editing = NameEdit(folderID: nil, initialName: "", initialColor: nil)
    }

    // The Mac's preference rows are denser than the iPhone's, so the tile is smaller.
    #if os(macOS)
    private static let iconSize = 22.0
    private static let rowSpacing = 10.0
    #else
    private static let iconSize = 29.0
    private static let rowSpacing = 12.0
    #endif

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

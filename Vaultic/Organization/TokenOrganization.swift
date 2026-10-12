import Foundation

/// A folder the user made for sorting tokens.
struct OrganizationItem: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: UUID
    var name: String
    /// `nil` shows the folder in the app's accent. Folders saved before colours
    /// existed decode as `nil`.
    var color: FolderColor?
}

/// Which folder each token is filed under, on this device.
///
/// This is deliberately separate from `OTPCode`. A folder is a way of looking at
/// tokens, not a property of them, so it stays out of the iCloud record, the merge
/// rule and the backup format. A reinstall or a second device starts with none filed.
struct TokenOrganization: Codable, Equatable, Sendable {
    /// The longest name a folder may have.
    static let maximumNameLength = 40

    private(set) var folders: [OrganizationItem] = []
    /// Folder id for each token that has one.
    private(set) var folderByToken: [UUID: UUID] = [:]

    /// What the Home list is showing.
    enum Filter: Equatable, Sendable {
        case all
        case folder(UUID)
    }

    // MARK: - Folders

    /// Adds a folder. Returns `nil` when the name is empty, too long, or already used
    /// by a folder, ignoring case.
    @discardableResult
    mutating func addFolder(named name: String, color: FolderColor? = nil) -> OrganizationItem? {
        guard let clean = Self.cleaned(name, among: folders) else { return nil }
        let item = OrganizationItem(id: UUID(), name: clean, color: color)
        folders.append(item)
        return item
    }

    /// Renames a folder. Returns `false` for a name that is not allowed.
    @discardableResult
    mutating func renameFolder(_ id: UUID, to name: String) -> Bool {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return false }
        let others = folders.filter { $0.id != id }
        guard let clean = Self.cleaned(name, among: others) else { return false }
        folders[index].name = clean
        return true
    }

    /// Sets or clears a folder's colour. Returns `false` if there is no such folder.
    @discardableResult
    mutating func setFolderColor(_ color: FolderColor?, for id: UUID) -> Bool {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return false }
        folders[index].color = color
        return true
    }

    /// Deletes a folder. Its tokens are left unfiled; the tokens themselves are untouched.
    mutating func deleteFolder(_ id: UUID) {
        folders.removeAll { $0.id == id }
        folderByToken = folderByToken.filter { $0.value != id }
    }

    // MARK: - Filing tokens

    /// The folder a token is in, if any. A folder that has been deleted reads as none.
    func folder(for token: UUID) -> OrganizationItem? {
        guard let folderID = folderByToken[token] else { return nil }
        return folders.first { $0.id == folderID }
    }

    mutating func setFolder(_ folderID: UUID?, for token: UUID) {
        if let folderID, folders.contains(where: { $0.id == folderID }) {
            folderByToken[token] = folderID
        } else {
            folderByToken[token] = nil
        }
    }

    /// The tokens that match a filter, in the order they were given.
    func filter(_ codes: [OTPCode], by filter: Filter) -> [OTPCode] {
        switch filter {
        case .all:
            return codes
        case .folder(let id):
            return codes.filter { folderByToken[$0.id] == id }
        }
    }

    /// Whether a filter still points at a folder that exists. Home falls back to
    /// `.all` when the one it shows has been deleted.
    func contains(_ filter: Filter) -> Bool {
        switch filter {
        case .all: return true
        case .folder(let id): return folders.contains { $0.id == id }
        }
    }

    /// The number of tokens in a folder, for its row in Settings.
    func count(inFolder id: UUID) -> Int {
        folderByToken.values.filter { $0 == id }.count
    }

    // MARK: - Names

    /// Trims a name and returns it when it may be used, or `nil`.
    private static func cleaned(_ name: String, among existing: [OrganizationItem]) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maximumNameLength else { return nil }
        let taken = existing.contains {
            $0.name.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        return taken ? nil : trimmed
    }
}

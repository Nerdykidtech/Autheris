import SwiftUI

/// The row of chips above the token list that narrows it to one folder.
///
/// Shown only when folders are on and there is at least one.
/// A chip is a plain button with its selected state in the accessibility traits,
/// so VoiceOver reads it as a choice rather than as a label.
struct OrganizationFilterBar: View {
    let organization: TokenOrganization
    @Binding var filter: TokenOrganization.Filter
    /// Called when a token is dropped on a folder chip: the token id, then the folder.
    var onFile: (UUID, UUID) -> Void = { _, _ in }
    /// The folder a dragged token is currently over, so its chip can show a ring.
    @State private var targetedFolder: UUID?
    /// Where the chips are, for the grid's grabber, which does not use a system drag.
    @Environment(FolderDropTargets.self) private var dropTargets

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                chip(String(localized: "All"), systemImage: "square.grid.2x2", selection: .all, tint: nil)

                ForEach(organization.folders) { folder in
                    chip(folder.name, systemImage: "folder", selection: .folder(folder.id),
                         tint: folder.color?.color,
                         isDropTarget: targetedFolder == folder.id || dropTargets.hoveredFolder == folder.id)
                        .onGeometryChange(for: CGRect.self) { proxy in
                            proxy.frame(in: .global)
                        } action: { frame in
                            dropTargets.frames[folder.id] = frame
                        }
                        .onDisappear {
                            dropTargets.frames[folder.id] = nil
                        }
                        .dropDestination(for: String.self) { items, _ in
                            var filed = false
                            for item in items {
                                if let token = UUID(uuidString: item) {
                                    onFile(token, folder.id)
                                    filed = true
                                }
                            }
                            return filed
                        } isTargeted: { isOver in
                            if isOver {
                                targetedFolder = folder.id
                            } else if targetedFolder == folder.id {
                                targetedFolder = nil
                            }
                        }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
        // The selected chip's fill is drawn over its edge, so the row is not clipped.
        .scrollClipDisabled()
    }

    /// `tint` is the folder's colour, or `nil` for the accent. A selected chip is filled
    /// with it, so a coloured folder is recognisable on the list as well as in Settings.
    private func chip(_ title: String, systemImage: String,
                      selection: TokenOrganization.Filter, tint: Color?,
                      isDropTarget: Bool = false) -> some View {
        let isSelected = filter == selection
        return Button {
            filter = selection
        } label: {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(foreground(isSelected: isSelected, tint: tint))
                .background(background(isSelected: isSelected, tint: tint), in: Capsule())
                .overlay {
                    // A ring while a dragged token hovers over the chip, to show where it lands.
                    if isDropTarget {
                        Capsule().strokeBorder(tint ?? Color.accentColor, lineWidth: 2)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// A selected chip is filled with its colour and carries white text. An unselected
    /// one keeps its colour in the text and a pale wash of it behind, so the colour
    /// shows before it is picked. A folder with no colour stays neutral.
    private func foreground(isSelected: Bool, tint: Color?) -> Color {
        if isSelected { return .white }
        return tint ?? .primary
    }

    private func background(isSelected: Bool, tint: Color?) -> AnyShapeStyle {
        if isSelected {
            return AnyShapeStyle(tint ?? Color.accentColor)
        }
        if let tint {
            return AnyShapeStyle(tint.opacity(0.18))
        }
        return AnyShapeStyle(Color.secondary.opacity(0.15))
    }
}

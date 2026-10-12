import SwiftUI

/// Lets a token be dragged onto a folder chip, while its list is being edited. The
/// token travels as its id, which the chip reads back.
///
/// Outside editing a card keeps its tap and long press, so the drag never competes
/// with copying a code. Each layout has its own idea of editing:
/// - the grid (iPad, and a wide Mac window) while Edit has it rearranging. Its cards
///   are reordered by their grabber, so the card itself is free to drag;
/// - the list on iPhone and iPad in Edit mode;
/// - the list in a narrow Mac window always: a Mac list has no Edit mode and drags
///   its rows directly, through the same item provider its reordering uses.
struct FilingDrag: ViewModifier {
    enum Layout {
        case list
        case grid(isRearranging: Bool)
    }

    let tokenID: UUID
    let layout: Layout

    #if os(iOS)
    @Environment(\.editMode) private var editMode
    #endif

    private var isEnabled: Bool {
        switch layout {
        case .grid(let isRearranging):
            return isRearranging
        case .list:
            #if os(iOS)
            return editMode?.wrappedValue.isEditing == true
            #else
            return true
            #endif
        }
    }

    func body(content: Content) -> some View {
        if !isEnabled {
            content
        } else if case .list = layout, usesListItemProvider {
            // A Mac list drags a row through its item provider, which is also what its
            // own reordering uses, so one drag can do either.
            content.itemProvider {
                NSItemProvider(object: tokenID.uuidString as NSString)
            }
        } else {
            // Anywhere else, including the Mac grid: `itemProvider` only starts a drag
            // inside a `List` or `Table`, so a card in a grid needs `draggable`.
            content.draggable(tokenID.uuidString)
        }
    }

    private var usesListItemProvider: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }
}

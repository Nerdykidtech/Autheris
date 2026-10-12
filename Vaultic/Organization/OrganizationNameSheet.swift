import SwiftUI

/// Asks for the name and colour of a folder, to add it or to change it.
///
/// Save stays with the caller's rule for what a name may be. A name it refuses keeps
/// the sheet open with a note, rather than closing as if it had been kept.
struct OrganizationNameSheet: View {
    let title: LocalizedStringKey
    let onSave: (String, FolderColor?) -> Bool

    @State private var name: String
    @State private var color: FolderColor?
    @State private var showsRefusal = false
    @Environment(\.dismiss) private var dismiss

    init(title: LocalizedStringKey, initialName: String, initialColor: FolderColor?,
         onSave: @escaping (String, FolderColor?) -> Bool) {
        self.title = title
        self.onSave = onSave
        _name = State(initialValue: initialName)
        _color = State(initialValue: initialColor)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .submitLabel(.done)
                        .onSubmit(save)
                } footer: {
                    if showsRefusal {
                        Text("That name is empty, too long, or already used. Names must be different from every other folder, ignoring capitals.")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    colorRow
                } header: {
                    Text("Color")
                }
            }
            .navigationTitle(title)
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
        }
        .platformSheetDetents()
        .platformSheetSize(minWidth: 420, minHeight: 300)
    }

    /// One swatch for the folder's default colour, then one for each colour.
    /// Wraps onto as many rows as the width needs, so all nine fit on any phone.
    private var colorRow: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], alignment: .leading, spacing: 8) {
            swatch(nil, label: "Default")
            ForEach(FolderColor.allCases) { option in
                swatch(option, label: option.displayName)
            }
        }
        .padding(.vertical, 4)
    }

    private func swatch(_ option: FolderColor?, label: LocalizedStringKey) -> some View {
        let isSelected = color == option
        return Button {
            color = option
        } label: {
            Circle()
                .fill(option?.color ?? Color.accentColor)
                .frame(width: 30, height: 30)
                .overlay {
                    if isSelected {
                        Circle()
                            .strokeBorder(Color.primary, lineWidth: 3)
                            .frame(width: 38, height: 38)
                    }
                }
                .frame(width: 38, height: 38)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func save() {
        guard canSave else { return }
        if onSave(name, color) {
            dismiss()
        } else {
            showsRefusal = true
        }
    }
}

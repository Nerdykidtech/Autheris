import SwiftUI

/// Asks for the name and colour of a folder, to add it or to change it.
///
/// Save stays with the caller's rule for what a name may be. A name it refuses keeps
/// the sheet open with a note, rather than closing as if it had been kept.
///
/// Laid out as each platform lays out its own sheets: on the Mac a title, a grouped
/// form and a row of buttons along the bottom; on iPhone and iPad a navigation sheet
/// with Cancel and Save in the bar.
struct OrganizationNameSheet: View {
    let title: LocalizedStringKey
    let onSave: (String, FolderColor?) -> Bool
    /// Offered as Delete when editing an existing folder; `nil` when adding one.
    var onDelete: (() -> Void)?

    @State private var name: String
    @State private var color: FolderColor?
    @State private var showsRefusal = false
    @State private var confirmingDelete = false
    @FocusState private var nameIsFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(title: LocalizedStringKey, initialName: String, initialColor: FolderColor?,
         onDelete: (() -> Void)? = nil,
         onSave: @escaping (String, FolderColor?) -> Bool) {
        self.title = title
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: initialName)
        _color = State(initialValue: initialColor)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        content
            .confirmationDialog("Delete Folder?", isPresented: $confirmingDelete,
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    onDelete?()
                    dismiss()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Its tokens stay in your list, just not in this folder.")
            }
    }

    // MARK: - Layouts

    #if os(macOS)
    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.top, 20)

            Form {
                Section {
                    // A Mac form labels the field itself: "Name" on the left, the field
                    // on the right, with a prompt so an empty field still shows where to type.
                    TextField("Name", text: $name, prompt: Text("Required"))
                        .focused($nameIsFocused)
                        .onSubmit(save)

                    LabeledContent("Color") {
                        HStack(spacing: 8) {
                            swatch(nil, label: "Default", diameter: 18)
                            ForEach(FolderColor.allCases) { option in
                                swatch(option, label: option.displayName, diameter: 18)
                            }
                        }
                    }
                } footer: {
                    if showsRefusal {
                        refusal
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            HStack(spacing: 12) {
                if onDelete != nil {
                    Button("Delete", role: .destructive) {
                        confirmingDelete = true
                    }
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        // Ready to type as soon as the sheet opens.
        .onAppear { nameIsFocused = true }
    }
    #else
    private var content: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .submitLabel(.done)
                        .onSubmit(save)
                } footer: {
                    if showsRefusal {
                        refusal
                    }
                }

                Section {
                    // Wraps onto as many rows as the width needs, so all nine fit.
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)],
                              alignment: .leading, spacing: 8) {
                        swatch(nil, label: "Default", diameter: 36)
                        ForEach(FolderColor.allCases) { option in
                            swatch(option, label: option.displayName, diameter: 36)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Color")
                }

                if onDelete != nil {
                    Section {
                        Button(role: .destructive) {
                            confirmingDelete = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    } footer: {
                        Text("Its tokens stay in your list, just not in this folder.")
                            .settingsFooterStyle()
                    }
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
    }
    #endif

    // MARK: - Parts

    private var refusal: some View {
        Text("That name is empty, too long, or already used. Names must be different from every other folder, ignoring capitals.")
            .foregroundStyle(.red)
    }

    /// One colour choice. `nil` is the folder's default, drawn as an empty circle with
    /// a slash so it reads as "no colour" rather than as another blue.
    private func swatch(_ option: FolderColor?, label: LocalizedStringKey, diameter: CGFloat) -> some View {
        let isSelected = color == option
        let ring: CGFloat = diameter < 24 ? 2 : 3
        return Button {
            color = option
        } label: {
            ZStack {
                if let option {
                    Circle().fill(option.color)
                } else {
                    Circle().strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1.5)
                    Image(systemName: "line.diagonal")
                        .font(.system(size: diameter * 0.55, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: diameter, height: diameter)
            .padding(ring + 2)
            .overlay {
                Circle().strokeBorder(isSelected ? Color.primary : Color.clear, lineWidth: ring)
            }
            .contentShape(Circle())
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

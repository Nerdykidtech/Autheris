import SwiftUI

/// A grid of emoji to use as a token's icon. Needs no network, so it is the way
/// to have a custom icon with "Fetch service logos" off.
struct EmojiIconPicker: View {
    /// Set to the emoji's PNG when one is picked; see `CustomIcon.emoji`.
    @Binding var selection: Data?
    @Environment(\.dismiss) private var dismiss

    /// Chosen to suit the things people put authenticator codes on, and kept to
    /// one unbroken grid so it needs no category headings to translate.
    static let choices = [
        "🔐", "🔑", "🗝️", "🛡️", "🔒", "🔓", "📱", "💻", "🖥️", "⌚",
        "📧", "💬", "🏦", "💳", "🛒", "📦", "🎮", "🎵", "📸", "🎬",
        "☁️", "🌐", "🌍", "🚀", "⚡", "🔥", "💧", "🌿", "🌲", "🍎",
        "🍊", "🍋", "🍇", "🍓", "🍕", "🍔", "☕", "🍺", "🚗", "✈️",
        "🚲", "🏠", "🏢", "🏫", "🏥", "🎓", "💼", "📚", "🧾", "💰",
        "🪙", "💎", "🏆", "🎯", "🧩", "🎨", "🖊️", "📝", "🔔", "⭐",
        "❤️", "😀", "😎", "🤖", "👾", "🦊", "🐱", "🐶", "🐼", "🦁",
        "🐸", "🐵", "🦄", "🐢", "🐙", "🦋", "🌈", "☀️", "🌙", "❄️",
        "🍀", "🌸", "🌻", "🎲", "⚽", "🏀", "🎸", "🎧", "🪴", "🧭"
    ]

    private let columns = [GridItem(.adaptive(minimum: 56), spacing: 8)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Self.choices, id: \.self) { emoji in
                    Button {
                        if let picked = CustomIcon.emoji(emoji) {
                            selection = picked
                            dismiss()
                        }
                    } label: {
                        Text(emoji)
                            .font(.system(size: 34))
                            .frame(width: 56, height: 56)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(emoji))
                }
            }
            .padding(16)
        }
        .navigationTitle("Emoji")
        .inlineNavigationTitle()
    }
}

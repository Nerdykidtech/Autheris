import SwiftUI

/// A page of Settings on iPhone and iPad.
///
/// The top level lists these, and each opens on its own: in a sidebar beside the
/// page on iPad, and pushed on iPhone. The Mac shows the same groups as the tabs of
/// its preferences window instead (`SettingsView.macPreferencesBody`).
///
/// The titles are the section headers the screen already had, so every one is
/// already translated.
enum SettingsPage: Hashable, CaseIterable, Identifiable {
    case privacy
    case sync
    case appearance
    case data
    case help

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .privacy: "Privacy"
        case .sync: "iCloud Sync"
        case .appearance: "Appearance"
        case .data: "Data"
        case .help: "Help"
        }
    }

    var systemImage: String {
        switch self {
        case .privacy: "hand.raised.fill"
        case .sync: "icloud.fill"
        case .appearance: "paintpalette.fill"
        case .data: "externaldrive.fill"
        case .help: "questionmark"
        }
    }

    /// The colour of the page's icon tile, as the system Settings app colours its own.
    var tint: Color {
        switch self {
        case .privacy: .blue
        case .sync: .cyan
        case .appearance: .pink
        case .data: .gray
        case .help: .orange
        }
    }
}

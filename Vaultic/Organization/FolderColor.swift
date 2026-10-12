import SwiftUI

/// The colour a folder is shown in. A folder with none shows in the app's accent.
///
/// Stored by name, so a palette change does not silently recolour existing folders.
enum FolderColor: String, CaseIterable, Codable, Identifiable, Sendable {
    case blue
    case teal
    case green
    case orange
    case pink
    case purple
    case red
    case gray

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .blue: .blue
        case .teal: .teal
        case .green: .green
        case .orange: .orange
        case .pink: .pink
        case .purple: .purple
        case .red: .red
        case .gray: .gray
        }
    }

    /// `LocalizedStringKey`, so VoiceOver reads the names in the user's language.
    var displayName: LocalizedStringKey {
        switch self {
        case .blue: "Blue"
        case .teal: "Teal"
        case .green: "Green"
        case .orange: "Orange"
        case .pink: "Pink"
        case .purple: "Purple"
        case .red: "Red"
        case .gray: "Gray"
        }
    }
}

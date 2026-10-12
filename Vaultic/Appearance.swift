import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

private func rgb(_ hex: UInt32) -> Color {
    Color(
        red: Double((hex >> 16) & 0xFF) / 255.0,
        green: Double((hex >> 8) & 0xFF) / 255.0,
        blue: Double(hex & 0xFF) / 255.0
    )
}

enum AccentTheme: String, CaseIterable, Identifiable {
    case indigo
    case cyan
    case emerald
    case amber
    case rose
    case slate
    case blue
    case violet
    case orange

    var id: String { rawValue }

    /// `LocalizedStringKey` so VoiceOver reads these in the user's language: as a
    /// `String` the literals never reach the catalog (see SettingsView's swatch row).
    var displayName: LocalizedStringKey {
        switch self {
        case .indigo: return "Indigo"
        case .cyan: return "Cyan"
        case .emerald: return "Emerald"
        case .amber: return "Amber"
        case .rose: return "Rose"
        case .slate: return "Slate"
        case .blue: return "Blue"
        case .violet: return "Violet"
        case .orange: return "Orange"
        }
    }

    var color: Color {
        switch self {
        case .indigo: return rgb(0x6366F1)
        case .cyan: return rgb(0x06B6D4)
        case .emerald: return rgb(0x10B981)
        case .amber: return rgb(0xF59E0B)
        case .rose: return rgb(0xF43F5E)
        case .slate: return rgb(0x64748B)
        case .blue: return rgb(0x3B82F6)
        case .violet: return rgb(0x8B5CF6)
        case .orange: return rgb(0xF97316)
        }
    }
}

/// Whether the app follows the system's light or dark setting, or always uses one.
///
/// Stored per device under `appearanceMode`. Unlike the accent it is not mirrored
/// into the Keychain, so a reinstall brings it back to `system`.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    /// `LocalizedStringKey`, as with `AccentTheme.displayName`, so the labels are
    /// translated.
    var displayName: LocalizedStringKey {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// The mode for a stored value. An unknown or empty value is `system`.
    static func stored(_ raw: String) -> AppearanceMode {
        AppearanceMode(rawValue: raw) ?? .system
    }

    /// Makes this mode the colour scheme of every open window.
    ///
    /// `preferredColorScheme` can't hand the scheme back to the system: passing `nil`
    /// after a window was set to Light or Dark leaves that scheme in place, so
    /// returning to System kept it. The window's own style is set instead, where
    /// `unspecified` means the system's setting again.
    @MainActor
    func apply() {
        #if os(iOS)
        let style: UIUserInterfaceStyle
        switch self {
        case .system: style = .unspecified
        case .light: style = .light
        case .dark: style = .dark
        }
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                window.overrideUserInterfaceStyle = style
            }
        }
        #elseif os(macOS)
        switch self {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        #endif
    }
}

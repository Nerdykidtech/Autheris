import SwiftUI

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

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .indigo: return "Indigo"
        case .cyan: return "Cyan"
        case .emerald: return "Emerald"
        case .amber: return "Amber"
        case .rose: return "Rose"
        case .slate: return "Slate"
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
        }
    }
}

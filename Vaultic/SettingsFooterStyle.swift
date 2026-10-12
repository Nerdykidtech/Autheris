import SwiftUI

extension View {
    /// How a Settings section footer reads: small and secondary, a little below the
    /// rows it explains.
    func settingsFooterStyle() -> some View {
        font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }
}

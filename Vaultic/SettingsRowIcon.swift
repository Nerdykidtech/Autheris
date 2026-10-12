import SwiftUI

/// The rounded, coloured icon tile beside each Settings page, as in the system
/// Settings app. It grows with Dynamic Type so it stays in proportion to the label.
struct SettingsRowIcon: View {
    let systemImage: String
    let tint: Color

    @ScaledMetric private var size: Double

    /// `size` is the tile's side at the default text size: 29 matches the iPhone's
    /// Settings rows, and a Mac preference list uses a smaller tile.
    init(systemImage: String, tint: Color, size: Double = 29) {
        self.systemImage = systemImage
        self.tint = tint
        _size = ScaledMetric(wrappedValue: size, relativeTo: .body)
    }

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint.gradient, in: .rect(cornerRadius: size * 0.24))
            // The label beside it already names the page.
            .accessibilityHidden(true)
    }
}

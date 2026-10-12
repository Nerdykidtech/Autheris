import SwiftUI

/// The rounded, coloured icon tile beside each Settings page, as in the system
/// Settings app. It grows with Dynamic Type so it stays in proportion to the label.
struct SettingsRowIcon: View {
    let systemImage: String
    let tint: Color

    @ScaledMetric(relativeTo: .body) private var size = 29.0

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

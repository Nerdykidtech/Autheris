import SwiftUI
import UIKit

extension Color {
    /// Parses `#RRGGBB` or `RRGGBB` (6 hex digits).
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") {
            s.removeFirst()
        }
        guard s.count == 6, s.allSatisfy(\.isHexDigit) else { return nil }
        guard let value = UInt32(s, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
    
    /// Uppercase `RRGGBB` for storage, or `nil` if the color cannot be resolved to RGB.
    func rgbHexStringForStorage() -> String? {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if ui.getRed(&r, green: &g, blue: &b, alpha: &a) {
            return String(
                format: "%02X%02X%02X",
                Int((r * 255).rounded()),
                Int((g * 255).rounded()),
                Int((b * 255).rounded())
            )
        }
        let cg = ui.cgColor
        guard let components = cg.components else { return nil }
        if cg.numberOfComponents == 2 {
            let gray = components[0]
            let v = Int((gray * 255).rounded())
            return String(format: "%02X%02X%02X", v, v, v)
        }
        if components.count >= 3 {
            return String(
                format: "%02X%02X%02X",
                Int((components[0] * 255).rounded()),
                Int((components[1] * 255).rounded()),
                Int((components[2] * 255).rounded())
            )
        }
        return nil
    }
}

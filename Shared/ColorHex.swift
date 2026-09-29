import SwiftUI

// `canImport` rather than `os(iOS)`: this file is compiled into the watch app
// too, and watchOS has UIKit as well — but a plain `os(iOS)` test would have left
// `UIColor` unnamed there. macOS is the platform that genuinely has no UIKit, and
// it takes the `usingColorSpace` branch below instead.
#if canImport(UIKit)
import UIKit
#endif

extension Color {
    /// Parses `#RRGGBB` or `RRGGBB` (6 hex digits).
    ///
    /// `nonisolated` because it is pure — it reads a string and returns a colour
    /// and touches nothing else. Without it the module's default `MainActor`
    /// isolation applies, and passing it as a function value
    /// (`flatMap(Color.init(hex:))`) hands a main-actor function to a nonisolated
    /// parameter, which the watch build warns about.
    nonisolated init?(hex: String) {
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
        #if os(macOS)
        // An AppKit semantic colour has no fixed components until it is resolved
        // into a concrete colour space, and asking an unresolved one either fails
        // or answers for whatever space the current display happens to be in.
        // Resolving to sRGB first is what makes the stored hex the same on every
        // Mac. `NSColor.getRed` also reports failure by *raising* rather than by
        // returning a flag, so reading the components is the safe route here.
        guard let color = PlatformColor(self).usingColorSpace(.sRGB),
              let components = color.cgColor.components else { return nil }
        return Self.hex(fromComponents: components)
        #else
        let color = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if color.getRed(&r, green: &g, blue: &b, alpha: &a) {
            return Self.hex(red: r, green: g, blue: b)
        }
        guard let components = color.cgColor.components else { return nil }
        return Self.hex(fromComponents: components)
        #endif
    }

    /// `RRGGBB` from a colour's components, treating a two-component (grayscale)
    /// colour as grey rather than rejecting it.
    private static func hex(fromComponents components: [CGFloat]) -> String? {
        if components.count == 2 {
            let v = Int((components[0] * 255).rounded())
            return String(format: "%02X%02X%02X", v, v, v)
        }
        guard components.count >= 3 else { return nil }
        return hex(red: components[0], green: components[1], blue: components[2])
    }

    private static func hex(red: CGFloat, green: CGFloat, blue: CGFloat) -> String {
        String(
            format: "%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )
    }
}

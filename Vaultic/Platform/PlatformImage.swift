import SwiftUI

#if os(macOS)
import AppKit

/// The image type SwiftUI views hold, whichever framework is underneath.
///
/// `UIImage` on iOS, `NSImage` on macOS. The app only ever needs three things
/// from it — decode `Data`, render into an `Image`, and encode back to PNG — so
/// a typealias plus the two shims below cover every call site.
typealias PlatformImage = NSImage

/// The colour type behind the handful of places that need a `CGColor` — the
/// camera overlay's `CALayer` borders.
typealias PlatformColor = NSColor

extension NSImage {
    /// Matches `UIImage(cgImage:)`, which is not failable.
    nonisolated static func from(cgImage: CGImage) -> NSImage {
        NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    /// Matches `UIImage.pngData()`, as a *method* rather than a property, so the
    /// call sites read identically on both platforms.
    func pngData() -> Data? {
        guard let tiff = tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// Matches `UIImage.cgImage` for the QR export path.
    var cgImageForExport: CGImage? {
        var rect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
#else
import UIKit

typealias PlatformImage = UIImage
typealias PlatformColor = UIColor

extension UIImage {
    nonisolated static func from(cgImage: CGImage) -> UIImage {
        UIImage(cgImage: cgImage)
    }

    var cgImageForExport: CGImage? { cgImage }
}
#endif

extension Image {
    /// `Image(uiImage:)` and `Image(nsImage:)` behind one spelling.
    init(platformImage: PlatformImage) {
        #if os(macOS)
        self.init(nsImage: platformImage)
        #else
        self.init(uiImage: platformImage)
        #endif
    }
}

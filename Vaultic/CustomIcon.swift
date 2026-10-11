import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Turns a picture the user picked into the bytes a token keeps.
///
/// ImageIO rather than `PlatformImage`, so the same code runs on iOS and macOS and
/// never holds a full-size photo in memory: the thumbnail is decoded at the size
/// it will be drawn, straight from the file's own data.
nonisolated enum CustomIcon {
    /// The sizes tried in turn, largest first. A 44-point icon on a 3x screen
    /// needs 132 pixels, so 160 leaves some room; a noisy photo may not fit in
    /// `maximumBytes` at that size, and then a smaller one is used instead.
    static let pixelSizes = [160, 128, 96]

    /// The most a token's picture may hold. The picture is part of the encrypted
    /// record it syncs in, and CloudKit caps a record at 1 MB; at these sizes a
    /// picture is a small fraction of that.
    static let maximumBytes = 64 * 1024

    /// The picture as PNG bytes, scaled to fit the largest of `pixelSizes` that
    /// keeps it under `maximumBytes`. `nil` when `data` is not an image, or when
    /// even the smallest size does not fit.
    static func prepared(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }

        for size in pixelSizes {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: size
            ]
            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
                  let png = pngData(for: thumbnail),
                  png.count <= maximumBytes else { continue }
            return png
        }
        return nil
    }

    /// An emoji drawn as a PNG, for a token whose icon the user picked from the
    /// emoji list. It is rendered once, here, so an emoji icon is stored and synced
    /// exactly like a photo and needs no network to show.
    @MainActor
    static func emoji(_ character: String) -> Data? {
        let renderer = ImageRenderer(content: Text(character).font(.system(size: 120)))
        renderer.scale = 2
        guard let image = renderer.cgImage,
              let png = pngData(for: image),
              png.count <= maximumBytes else { return nil }
        return png
    }

    private static func pngData(for image: CGImage) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

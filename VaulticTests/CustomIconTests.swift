import XCTest
import CloudKit
import ImageIO
import UniformTypeIdentifiers
@testable import Vaultic

/// The picture a token can keep in place of the service's logo: how a picture
/// is prepared, how it is carried in JSON and in the sync record, and that the
/// watch never receives it.
@MainActor
final class CustomIconTests: XCTestCase {

    // MARK: - Preparing a picture

    func testAPhotoIsScaledDownToTheIconSizeAndKeptUnderTheLimit() throws {
        let photo = try makePNG(width: 1600, height: 1200, noisy: false)

        let prepared = try XCTUnwrap(CustomIcon.prepared(from: photo))

        XCTAssertLessThanOrEqual(prepared.count, CustomIcon.maximumBytes)
        let size = try pixelSize(of: prepared)
        XCTAssertLessThanOrEqual(max(size.width, size.height), CGFloat(CustomIcon.pixelSizes[0]))
    }

    func testANoisyPictureStillComesOutUnderTheLimit() throws {
        let noisy = try makePNG(width: 1000, height: 1000, noisy: true)

        let prepared = try XCTUnwrap(CustomIcon.prepared(from: noisy))

        XCTAssertLessThanOrEqual(prepared.count, CustomIcon.maximumBytes)
        let size = try pixelSize(of: prepared)
        XCTAssertLessThanOrEqual(max(size.width, size.height), CGFloat(CustomIcon.pixelSizes[0]))
    }

    @MainActor
    func testAnEmojiBecomesASmallPNG() throws {
        let emoji = try XCTUnwrap(CustomIcon.emoji("🔐"))

        XCTAssertLessThanOrEqual(emoji.count, CustomIcon.maximumBytes)
        XCTAssertNotNil(CGImageSourceCreateWithData(emoji as CFData, nil))
    }

    /// Lion and compass render over the limit at full size; they must still come
    /// out as a picture, not nil (which made the tap do nothing).
    @MainActor
    func testEmojiThatIsLargeAtFullSizeStillBecomeAPicture() throws {
        for emoji in ["🦁", "🧭"] {
            let picture = try XCTUnwrap(CustomIcon.emoji(emoji), emoji)

            XCTAssertLessThanOrEqual(picture.count, CustomIcon.maximumBytes, emoji)
            XCTAssertNotNil(CGImageSourceCreateWithData(picture as CFData, nil), emoji)
        }
    }

    func testDataThatIsNotAPictureIsRefused() {
        XCTAssertNil(CustomIcon.prepared(from: Data("not a picture".utf8)))
    }

    // MARK: - JSON (backups and Transfer QR codes)

    func testACustomIconRoundTripsThroughJSON() throws {
        let icon = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])
        let original = OTPCode(label: "Example", account: "user", secret: "JBSWY3DPEHPK3PXP", customIcon: icon)

        let decoded = try JSONDecoder().decode(OTPCode.self, from: JSONEncoder().encode(original))

        XCTAssertEqual(decoded.customIcon, icon)
    }

    func testATokenWithoutAPictureDecodesWithNone() throws {
        // A token saved before custom icons existed has no `customIcon` key at all.
        let original = OTPCode(label: "Example", account: "user", secret: "JBSWY3DPEHPK3PXP")

        let decoded = try JSONDecoder().decode(OTPCode.self, from: JSONEncoder().encode(original))

        XCTAssertNil(decoded.customIcon)
    }

    // MARK: - Sync record

    func testThePictureSyncsAsEncryptedText() throws {
        let icon = Data(repeating: 9, count: 300)
        let id = UUID()

        let record = CloudKitTokenSyncService.encode(.live(makeToken(id: id, customIcon: icon)))

        XCTAssertEqual(record.encryptedValues["customIcon"] as? String, icon.base64EncodedString())
        XCTAssertNil(record["customIcon"], "a picture is never stored as a readable field")
        let decoded = try XCTUnwrap(CloudKitTokenSyncService.decode(record)?.token)
        XCTAssertEqual(decoded.customIcon, icon)
    }

    func testRemovingThePictureClearsItOnTheServerRecord() throws {
        let id = UUID()
        let existing = CloudKitTokenSyncService.encode(.live(makeToken(id: id, customIcon: Data([1, 2]))))

        let record = CloudKitTokenSyncService.encode(.live(makeToken(id: id)), into: existing)

        XCTAssertNil(record.encryptedValues["customIcon"])
        XCTAssertNil(CloudKitTokenSyncService.decode(record)?.token?.customIcon)
    }

    // MARK: - Watch

    func testTheWatchPayloadLeavesOutPictures() throws {
        let blob = try WatchTokenPayload.encode([makeToken(customIcon: Data(repeating: 7, count: 1000))])

        let decoded = try XCTUnwrap(WatchTokenPayload.decode(blob))

        XCTAssertEqual(decoded.tokens.first?.label, "GitHub")
        XCTAssertNil(decoded.tokens.first?.customIcon)
    }

    // MARK: - Helpers

    private func makeToken(id: UUID = UUID(), customIcon: Data? = nil) -> OTPCode {
        OTPCode(id: id, label: "GitHub", account: "octocat", secret: "JBSWY3DPEHPK3PXP",
                customIcon: customIcon, modifiedAt: Date(timeIntervalSince1970: 1_000))
    }

    /// A PNG of the given size. `noisy` fills it with random pixels, which PNG
    /// cannot compress; otherwise it is a smooth gradient.
    private func makePNG(width: Int, height: Int, noisy: Bool) throws -> Data {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for row in 0..<height {
            for column in 0..<width {
                let offset = (row * width + column) * 4
                pixels[offset] = noisy ? UInt8.random(in: 0...255) : UInt8(column * 255 / width)
                pixels[offset + 1] = noisy ? UInt8.random(in: 0...255) : UInt8(row * 255 / height)
                pixels[offset + 2] = noisy ? UInt8.random(in: 0...255) : 128
            }
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        let image = try XCTUnwrap(CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func pixelSize(of png: Data) throws -> CGSize {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return CGSize(width: image.width, height: image.height)
    }
}

import XCTest
import SwiftUI
@testable import Vaultic

/// `IssuerBranding` gives each token its ring colour and the key its logo is
/// cached under. Both used to come from `hashValue`, which Swift seeds randomly
/// per launch; these pin them to values that cannot drift between launches, and
/// to the ones Android computes for the same label.
final class IssuerBrandingTests: XCTestCase {

    // MARK: - Fallback colour

    func testFNV1aMatchesTheReferenceVectors() {
        // From the FNV reference test suite, so a slip in the constants shows here
        // rather than as a silently different palette.
        XCTAssertEqual(IssuerBranding.fnv1a(""), 0x811C_9DC5)
        XCTAssertEqual(IssuerBranding.fnv1a("a"), 0xE40C_292C)
        XCTAssertEqual(IssuerBranding.fnv1a("foobar"), 0xBF9C_F968)
    }

    func testFallbackIndexMatchesAndroid() {
        // Computed with the FNV-1a in Android's `IssuerBranding.kt`. If these move,
        // the same service shows a different colour on each platform.
        XCTAssertEqual(IssuerBranding.fnv1a("bitwarden"), 0xB1C3_72D9)
        XCTAssertEqual(IssuerBranding.fallbackPaletteIndex(for: "bitwarden"), 1)
        XCTAssertEqual(IssuerBranding.fallbackPaletteIndex(for: "1password"), 3)
        XCTAssertEqual(IssuerBranding.fallbackPaletteIndex(for: "proton"), 5)
        // Hashed as UTF-8 bytes, not UTF-16 units or scalars.
        XCTAssertEqual(IssuerBranding.fallbackPaletteIndex(for: "société générale"), 4)
    }

    func testForLabelUsesThePinnedPaletteColour() {
        XCTAssertEqual(IssuerBranding.forLabel("Bitwarden").color, IssuerBranding.fallbackPalette[1])
        XCTAssertEqual(IssuerBranding.forLabel("Proton").color, IssuerBranding.fallbackPalette[5])
    }

    func testSameLabelGivesSameColourIgnoringCaseAndWhitespace() {
        let colour = IssuerBranding.forLabel("Bitwarden").color
        XCTAssertEqual(IssuerBranding.forLabel("Bitwarden").color, colour)
        XCTAssertEqual(IssuerBranding.forLabel("  BITWARDEN\n").color, colour)
        XCTAssertNil(IssuerBranding.forLabel("Bitwarden").domain)
    }

    // MARK: - Cache key

    func testCacheKeyIsTheLowercasedCompanyNameOnly() {
        XCTAssertEqual(IssuerBranding.forLabel("Bitwarden").cacheKey, "name_bitwarden")
        XCTAssertEqual(IssuerBranding.forLabel("My-Bank (Work)").cacheKey, "name_my bank work")
        XCTAssertEqual(IssuerBranding.forLabel("GitHub").cacheKey, "name_github")
    }

    func testSameLabelGivesSameCacheKey() {
        XCTAssertEqual(
            IssuerBranding.forLabel("Proton").cacheKey,
            IssuerBranding.forLabel("Proton").cacheKey
        )
        XCTAssertEqual(IssuerBranding.forLabel("Proton"), IssuerBranding.forLabel("Proton"))
    }

    // MARK: - Brand matches

    func testBrandMatchesAreUnchanged() {
        let cases: [(label: String, domain: String, rgb: UInt32)] = [
            ("GitHub", "github.com", 0x8E8E93),
            ("Google", "google.com", 0x4285F4),
            ("Gmail", "google.com", 0x4285F4),
            ("AWS", "aws.amazon.com", 0xFF9900),
            ("Amazon", "aws.amazon.com", 0xFF9900),
            ("Microsoft", "microsoft.com", 0x0078D4),
            ("Azure", "microsoft.com", 0x0078D4),
            ("Office 365", "microsoft.com", 0x0078D4),
            ("Dropbox", "dropbox.com", 0x0061FF),
            ("Discord", "discord.com", 0x5865F2),
            ("Slack", "slack.com", 0x4A154B),
            ("Notion", "notion.so", 0x8E8E93),
            ("GitLab", "gitlab.com", 0xFC6D26),
            ("Bitbucket", "bitbucket.org", 0x0052CC),
        ]
        for (label, domain, rgb) in cases {
            let branding = IssuerBranding.forLabel(label)
            XCTAssertEqual(branding.domain, domain, label)
            XCTAssertEqual(branding.color, color(rgb), label)
            XCTAssertEqual(branding.displayName, label, label)
        }
    }

    // MARK: - Migrating the old cache

    func testLegacyHashSuffixedFilesAreRenamedOnceAndDuplicatesDropped() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        func write(_ name: String) throws {
            try Data(name.utf8).write(to: dir.appendingPathComponent(name))
        }
        // Two launches' worth of the same logo, one with a negative hash.
        try write("name_bitwarden_123456789.png")
        try write("name_bitwarden_-987654321.png")
        try write("name_my bank work_42.png")
        // Already under the new key: must survive untouched.
        try write("name_proton.png")
        try write("name_proton_7.png")

        LogoCacheManager.migrateLegacyFiles(in: dir, fileManager: fm)

        let names = Set(try fm.contentsOfDirectory(atPath: dir.path))
        XCTAssertEqual(names, ["name_bitwarden.png", "name_my bank work.png", "name_proton.png"])
        XCTAssertEqual(
            try Data(contentsOf: dir.appendingPathComponent("name_proton.png")),
            Data("name_proton.png".utf8)
        )

        // Running it again over migrated files changes nothing.
        LogoCacheManager.migrateLegacyFiles(in: dir, fileManager: fm)
        XCTAssertEqual(Set(try fm.contentsOfDirectory(atPath: dir.path)), names)
    }

    private func color(_ value: UInt32) -> Color {
        Color(
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0
        )
    }
}

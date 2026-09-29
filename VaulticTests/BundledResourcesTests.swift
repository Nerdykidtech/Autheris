import XCTest
@testable import Vaultic

/// Guards the app bundle against shipping developer material.
///
/// `Vaultic/` is a `PBXFileSystemSynchronizedRootGroup`, and such a folder copies
/// **every** non-Swift file it contains into the bundle as a resource. That is not
/// theoretical: a Teenybase/Cloudflare Workers scaffold used to live at
/// `Vaultic/backend/`, and its `.dev.vars` — real JWT secrets, an admin service
/// token, a Mailgun key — was being shipped inside `Autheris.app`, readable by
/// anyone who downloaded it. The scaffold is gone now, but `CLAUDE.md` and
/// `.mcp.json` still live in that folder and still must not ship, and the next
/// developer file added there would be copied in the same silent way.
///
/// A folder can only be told to leave files out **one at a time** — listing a
/// directory does not exclude its contents, which was measured rather than assumed
/// — so the exclusion list in `Vaultic.xcodeproj/project.pbxproj` is the only thing
/// keeping them out. A blacklist that nothing checks is a blacklist that rots, and
/// this one did go unnoticed for months. Hence these tests.
///
/// This suite previously also searched every bundled file for the `.dev.vars` key
/// names, which is what actually caught that leak, and it was verified by
/// deliberately removing the exclusion and watching it fail. That check was retired
/// when the secrets themselves were deleted — searching for strings that no longer
/// exist anywhere would have been a test that could not fail. **If secret material
/// is ever reintroduced under `Vaultic/`, restore it.**
final class BundledResourcesTests: XCTestCase {

    /// The app's own bundle, not the test bundle.
    ///
    /// Asserted rather than assumed: `Bundle.main` is the *host* app while tests
    /// run inside it, but if that ever stopped being true this suite would
    /// cheerfully inspect the wrong bundle and pass while developer material
    /// shipped.
    private var appBundle: Bundle {
        let bundle = Bundle.main
        XCTAssertEqual(
            bundle.bundleIdentifier,
            "com.eddingtontech.autheris",
            "Bundle.main is not the Autheris app, so these assertions would be inspecting nothing."
        )
        return bundle
    }

    /// Every regular file in the app bundle, at any depth — excluding the test
    /// bundle itself.
    ///
    /// Enumerated from the whole bundle rather than from `resourceURL`, because for
    /// a Mac app that would only cover `Contents/Resources` and miss the executable
    /// and `Info.plist` under `Contents/`.
    ///
    /// While tests run, `VaulticTests.xctest` is nested inside the host app at
    /// `PlugIns/`, and it is the one thing in there carrying developer material —
    /// this file's own compiled code. It is a build-time artefact of running the
    /// tests and a shipping app has no `PlugIns/*.xctest`, so its subtree is
    /// skipped. Only `.xctest` bundles are skipped, so an app extension added later
    /// is still scanned.
    private func bundledFiles() throws -> [URL] {
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(at: appBundle.bundleURL, includingPropertiesForKeys: [.isRegularFileKey]),
            "Could not enumerate the app bundle."
        )
        return enumerator.compactMap { $0 as? URL }.filter { url in
            !url.pathComponents.contains { $0.hasSuffix(".xctest") }
        }
    }

    // MARK: - What must not be there

    /// Developer material, by name and by shape.
    ///
    /// Both forms are needed. The names catch the files that are in `Vaultic/`
    /// today; the *shapes* catch a renamed or newly-added one, which is the case a
    /// name list alone misses — and the case that matters, because the previous
    /// leak was a file nobody was looking for. The dotfile rule is the broadest of
    /// the three: `.dev.vars`, `.env` and `.mcp.json` are all caught by it
    /// whatever they are called afterwards.
    func testNoDeveloperFilesAreBundled() throws {
        let forbiddenNames: Set<String> = [
            ".mcp.json",
            "CLAUDE.md",
            "package.json",
            "wrangler.toml",
            "teenybase.ts",
        ]

        /// Extensions that belong to a developer's tooling, not to an app. Adding
        /// an app resource of one of these types is a deliberate act — a `.md`
        /// shipped on purpose is almost certainly a mistake, so failing here and
        /// making someone look is the point.
        let forbiddenExtensions: Set<String> = [
            "md", "markdown", "toml", "ts", "yml", "yaml", "env", "vars", "lock",
        ]

        /// `.DS_Store` is operating-system noise rather than developer material,
        /// and it is not worth failing a build over.
        let toleratedDotfiles: Set<String> = [".DS_Store"]

        var offenders: [String] = []
        for url in try bundledFiles() {
            let name = url.lastPathComponent
            if forbiddenNames.contains(name) {
                offenders.append("\(name) (name)")
            } else if forbiddenExtensions.contains(url.pathExtension.lowercased()) {
                offenders.append("\(name) (.\(url.pathExtension))")
            } else if name.hasPrefix(".") && !toleratedDotfiles.contains(name) {
                offenders.append("\(name) (hidden file)")
            }
        }

        XCTAssertEqual(
            offenders.sorted(), [],
            "Developer material is inside the app bundle and would ship to every user. "
            + "Add the offending entry to membershipExceptions in Vaultic.xcodeproj/project.pbxproj. Found: \(offenders.sorted())"
        )
    }

    // MARK: - What must still be there

    /// The negative check above would also pass on an empty bundle, so this pins
    /// that the app's real content is still being copied. Without it, a broken copy
    /// phase would look exactly like success.
    func testTheAppStillBundlesItsOwnContent() throws {
        let names = Set(try bundledFiles().map(\.lastPathComponent))

        XCTAssertTrue(names.contains("Autheris"), "The app executable is missing from its own bundle.")
        XCTAssertTrue(names.contains("Assets.car"), "The asset catalogue is missing from the bundle.")
        XCTAssertTrue(names.contains("Info.plist"), "The app's Info.plist is missing from the bundle.")
    }
}

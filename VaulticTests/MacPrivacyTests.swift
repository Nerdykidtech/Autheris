#if os(macOS)
import AppKit
import XCTest
@testable import Vaultic

/// The Mac halves of the privacy protections that can't be checked through
/// `PrivacyShield`'s pure rules: where the cover is drawn, and what happens to a
/// copied code when the app quits.
///
/// `async` throughout: these make and drop main-actor objects, and freeing one in
/// a synchronous test crashes the Swift runtime (`swift_task_deinitOnExecutor`).
@MainActor
final class MacPrivacyTests: XCTestCase {

    override func tearDown() async throws {
        PrivacyShieldWindow.show(.hidden)
        try await super.tearDown()
    }

    private func openWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSView()
        window.orderFront(nil)
        addTeardownBlock { @MainActor in window.close() }
        return window
    }

    /// A sheet or the Settings window is a window of its own, which the cover in
    /// the main window's root view never reached.
    func testTheCoverIsDrawnOverEveryOpenWindow() async {
        let main = openWindow()
        let secondary = openWindow()

        PrivacyShieldWindow.show(.cover)

        for window in [main, secondary] {
            XCTAssertEqual(window.contentView?.subviews.count, 1, "every window the app has open is covered")
            XCTAssertEqual(window.contentView?.subviews.first?.frame, window.contentView?.bounds)
        }
    }

    func testTheCoverComesOffWhenTheAppReturns() async {
        let window = openWindow()

        PrivacyShieldWindow.show(.cover)
        PrivacyShieldWindow.show(.hidden)

        XCTAssertEqual(window.contentView?.subviews.count, 0)
    }

    func testShowingTheSameStyleAgainDoesNotStackCovers() async {
        let window = openWindow()

        PrivacyShieldWindow.show(.blur)
        PrivacyShieldWindow.show(.blur)
        PrivacyShieldWindow.show(.cover)

        XCTAssertEqual(window.contentView?.subviews.count, 1)
    }

    // MARK: - Copied codes

    /// Runs `body` with the user's own clipboard put back afterwards.
    private func preservingPasteboard(_ body: () -> Void) {
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.string(forType: .string)
        body()
        pasteboard.clearContents()
        if let saved { pasteboard.setString(saved, forType: .string) }
    }

    /// The Mac pasteboard has no expiry, so a code copied just before quitting
    /// stayed on the clipboard for good.
    func testQuittingClearsACopiedCode() async {
        preservingPasteboard {
            ClipboardHelper.copy("123456")
            ClipboardHelper.clearPendingCopy()

            XCTAssertNil(NSPasteboard.general.string(forType: .string))
        }
    }

    func testQuittingLeavesWhateverTheUserCopiedSince() async {
        preservingPasteboard {
            ClipboardHelper.copy("123456")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("the user's own text", forType: .string)
            ClipboardHelper.clearPendingCopy()

            XCTAssertEqual(NSPasteboard.general.string(forType: .string), "the user's own text")
        }
    }
}
#endif

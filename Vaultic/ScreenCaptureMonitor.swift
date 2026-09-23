#if os(iOS)
import UIKit
#endif

/// The platform's half of the screen-capture protection: the only part that has
/// to ask the operating system a question, kept away from `PrivacyShield` so the
/// rules themselves can be unit tested without a simulator.
///
/// `PrivacyShield` decides what to *do* when the screen is being captured. This
/// answers whether it is — and on the Mac the answer is that it cannot be asked,
/// which is why `WindowCaptureExclusion` exists.
@MainActor
enum ScreenCaptureMonitor {

    /// `true` when app content is being recorded or mirrored.
    ///
    /// Capture is the only exposure the app can observe here. A screenshot
    /// deliberately produces no notification — it is a single frame taken
    /// without the app's involvement — so it cannot be defended against this
    /// way, and nothing in the app pretends otherwise.
    ///
    /// On the Mac this is always `false`, because macOS gives an app no way to
    /// know: there is no `UIScreen.isCaptured` equivalent, and ScreenCaptureKit
    /// tells the capturer rather than the captee. The Mac does not leave that as
    /// a gap — it excludes its windows from capture outright, so there is
    /// nothing to notice. Answering `false` here is what stops the app claiming
    /// a detection it never actually made.
    static var isCaptured: Bool {
        #if os(iOS)
        // `UIScreen.main` is not used: it is deprecated as of iOS 26, and the
        // window scene's own screen is the one the user is actually looking at
        // when a device is mirrored to more than one destination.
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .contains { $0.screen.isCaptured }
        #else
        false
        #endif
    }
}

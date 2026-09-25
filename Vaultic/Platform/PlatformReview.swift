import Foundation
import StoreKit
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// The system's App Store review prompt.
///
/// `AppStore.requestReview(in:)` anchors to a platform-specific object — the
/// active `UIWindowScene` on iOS, the key window's `NSViewController` on macOS —
/// so the difference is named once here instead of branched at every call site,
/// in the same spirit as `Haptics` in `PlatformFeedback.swift`.
///
/// Nothing is returned, because nothing is knowable: the system may show the
/// prompt or silently drop the request, and an app cannot tell which happened.
/// Anything that needs to avoid asking twice has to keep its own record — see
/// `ReviewPrompt`.
@MainActor
enum PlatformReview {
    /// Raise the prompt, if the system chooses to show it.
    static func request() {
        #if os(iOS)
        guard let scene = foregroundScene else { return }
        AppStore.requestReview(in: scene)
        #else
        guard let controller = anchorController else { return }
        AppStore.requestReview(in: controller)
        #endif
    }

    #if os(iOS)
    /// The scene to anchor the prompt to.
    ///
    /// The active one comes first so that on iPad the prompt belongs to the
    /// window the user is actually looking at, rather than to another window of
    /// the same app.
    private static var foregroundScene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }
    #else
    /// The Mac asks against a view controller rather than a window, so the key
    /// window's is the one in front of the user. `mainWindow` covers the case
    /// where the app is frontmost but not key.
    private static var anchorController: NSViewController? {
        NSApplication.shared.keyWindow?.contentViewController
            ?? NSApplication.shared.mainWindow?.contentViewController
    }
    #endif
}

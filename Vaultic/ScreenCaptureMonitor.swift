import UIKit

/// UIKit-only half of the screen-capture protection.
///
/// Deliberately free of SwiftUI so the "is the screen being captured?" question
/// can be answered and type-checked without building a view.
///
/// `UIScreen.main` is not used: it is deprecated as of iOS 26, and the window
/// scene's own screen is the one the user is actually looking at when a device
/// is mirrored to more than one destination.
@MainActor
enum ScreenCaptureMonitor {

    /// `true` when any window scene currently showing app content is being
    /// recorded or mirrored.
    ///
    /// Capture is the only exposure the app can observe here. A screenshot
    /// deliberately produces no notification — it is a single frame taken
    /// without the app's involvement — so it cannot be defended against this
    /// way, and nothing in the app pretends otherwise.
    static var isCaptured: Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .contains { $0.screen.isCaptured }
    }
}

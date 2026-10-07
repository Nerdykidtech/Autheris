#if os(iOS)
import SwiftUI
import UIKit

/// The privacy cover, drawn in a window of its own above everything the app
/// shows.
///
/// It used to be a view in each window's root `ZStack`. Sheets are presented
/// above that root, so the cover hid the token list and nothing in front of it:
/// the app switcher, and a screen recording, showed an open Edit sheet's code,
/// a revealed setup key, or the Transfer QR code that holds every secret. A
/// window at a level above the app's own covers sheets, alerts and menus alike.
///
/// `PrivacyShield` still decides *when*; this only decides where it is drawn.
@MainActor
enum PrivacyShieldWindow {
    /// What the shield shows.
    enum Style: Equatable {
        /// Nothing: the app is in front and not being captured.
        case hidden
        /// A blur over everything, for "Blur when backgrounded".
        case blur
        /// The full privacy screen, for "Hide in app switcher" and capture.
        case cover
    }

    /// One shield per scene, kept while shown so it isn't rebuilt on every
    /// notification.
    private static var windows: [ObjectIdentifier: UIWindow] = [:]
    private static var style: Style = .hidden

    static func show(_ newStyle: Style) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard newStyle != .hidden else {
            windows.values.forEach { $0.isHidden = true }
            windows.removeAll()
            style = .hidden
            return
        }

        let styleChanged = newStyle != style
        style = newStyle
        for scene in scenes {
            let key = ObjectIdentifier(scene)
            let window = windows[key] ?? UIWindow(windowScene: scene)
            // Above the app's windows, its sheets and its alerts.
            window.windowLevel = .alert + 1
            if styleChanged || window.rootViewController == nil {
                window.rootViewController = controller(for: newStyle)
            }
            window.isHidden = false
            windows[key] = window
        }
    }

    private static func controller(for style: Style) -> UIViewController {
        switch style {
        case .cover:
            let host = UIHostingController(rootView: PrivacyOverlay())
            host.view.backgroundColor = .clear
            return host
        case .blur, .hidden:
            let controller = UIViewController()
            let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
            blur.frame = controller.view.bounds
            blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            controller.view.backgroundColor = .clear
            controller.view.addSubview(blur)
            return controller
        }
    }
}
#endif

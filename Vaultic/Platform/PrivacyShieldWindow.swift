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
#elseif os(macOS)
import AppKit
import SwiftUI

/// The privacy cover on the Mac, drawn over every window the app has open.
///
/// The cover in each window's root `ZStack` hides that window's own content and
/// nothing in front of it. A Mac sheet is a window of its own attached above the
/// main one, and the preferences window is outside the window group entirely, so
/// switching to another app left an open Edit sheet's code, a revealed setup key
/// or the Transfer QR code readable on screen.
///
/// iOS draws the cover in one window above the app's. A Mac app can't do that
/// without its cover also floating over the other apps the user switched to, so
/// instead the cover is laid over the content of each of the app's windows —
/// main windows, sheets and Settings alike — from this one place.
///
/// `PrivacyShield` still decides *when*; this only decides where it is drawn.
@MainActor
enum PrivacyShieldWindow {
    /// What the shield shows.
    enum Style: Equatable {
        /// Nothing: the app is in front.
        case hidden
        /// A blur over everything, for "Blur when backgrounded".
        case blur
        /// The full privacy screen, for "Hide in app switcher".
        case cover
    }

    /// The cover laid on each window, so it can be taken off again. A window
    /// that has gone takes its cover with it; a new one at the same address is
    /// told apart by the cover not being in its content.
    private static var shields: [ObjectIdentifier: NSView] = [:]
    private static var style: Style = .hidden

    static func show(_ newStyle: Style) {
        if newStyle != style {
            removeAll()
            style = newStyle
        }
        guard newStyle != .hidden else { return }
        for window in NSApplication.shared.windows where window.isVisible {
            cover(window)
        }
    }

    private static func cover(_ window: NSWindow) {
        guard let content = window.contentView else { return }
        let key = ObjectIdentifier(window)
        if let existing = shields[key], existing.superview === content { return }

        let shield = makeShield(for: style)
        shield.frame = content.bounds
        shield.autoresizingMask = [.width, .height]
        content.addSubview(shield, positioned: .above, relativeTo: nil)
        // SwiftUI can add views of its own to the window while it is covered — a
        // representable appearing — and those would be drawn above a cover that
        // was added first. The layer keeps it on top.
        shield.wantsLayer = true
        shield.layer?.zPosition = 1_000
        shields[key] = shield
    }

    private static func removeAll() {
        shields.values.forEach { $0.removeFromSuperview() }
        shields.removeAll()
    }

    private static func makeShield(for style: Style) -> NSView {
        // Blurs what is behind it within the window, and takes the clicks that
        // land on it, so nothing under the cover can be clicked through it.
        let blur = NSVisualEffectView()
        blur.blendingMode = .withinWindow
        blur.material = .hudWindow
        blur.state = .active
        if style == .cover {
            let host = NSHostingView(rootView: PrivacyOverlay())
            host.frame = blur.bounds
            host.autoresizingMask = [.width, .height]
            blur.addSubview(host)
        }
        return blur
    }
}
#endif

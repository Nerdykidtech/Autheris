import Combine
import SwiftUI

#if os(macOS)
import AppKit

/// The structural half of the screen-capture protection: keeping app content out
/// of a capture rather than reacting to one.
///
/// iOS can *notice* a recording — `UIScreen.isCaptured` changes under the app's
/// feet — and so it reacts, with the overlay `PrivacyShield` decides on. macOS
/// deliberately cannot be asked: there is no `UIScreen.isCaptured` equivalent,
/// because ScreenCaptureKit tells the *capturer* rather than the captee. An app
/// that wanted to detect capture on the Mac would have to poll
/// `CGWindowListCopyWindowInfo` and guess, which is not something a security
/// feature should be built on.
///
/// So the Mac does not try to detect capture. It makes its windows uncapturable
/// in the first place, via `NSWindow.sharingType = .none`, which is the stronger
/// of the two outcomes: the iOS path reacts a beat after recording begins, while
/// this one never lets the pixels out at all.
///
/// The honest trade-off, and the reason this is wired to the user's "Hide codes
/// when screen captured" preference rather than being unconditional: `.none`
/// also excludes the window from the user's *own* screenshots and screen
/// recordings. Someone who has turned that setting off is left alone.
@MainActor
final class WindowCaptureExclusion: ObservableObject {

    /// Whether the app is currently excluding its windows from capture.
    @Published private(set) var isExcluding = false

    /// Re-applies the setting whenever a window comes forward. A sheet is a
    /// window of its own, and one opened after the setting was applied — Edit,
    /// View Secret, the Transfer QR code — would otherwise stay capturable,
    /// since nothing in the view that hosts this redraws when a sheet opens.
    /// Never removed: this object lives as long as the app does.
    private var windowObservers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        windowObservers = [NSWindow.didBecomeKeyNotification, NSWindow.didBecomeMainNotification].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.apply() }
            }
        }
    }

    /// Applies, or lifts, the exclusion across every window the app owns.
    func setExcluding(_ excluding: Bool) {
        guard excluding != isExcluding else { return }
        isExcluding = excluding
        apply()
    }

    /// Re-applies the current setting. Called for each window as it appears,
    /// because a window that opens *after* the setting was turned on would
    /// otherwise never be told about it.
    func apply() {
        for window in NSApplication.shared.windows {
            // `.readOnly` is a window's ordinary capturable state (it is the
            // modern spelling of the old `.readWrite`, which macOS 15 deprecated);
            // `.none` is what takes it out of every capture.
            window.sharingType = isExcluding ? .none : .readOnly
        }
    }
}

/// Attaches `WindowCaptureExclusion` to the window that hosts the view.
private struct WindowAccessor: NSViewRepresentable {
    let onWindowAvailable: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        // The window is nil during `makeNSView` — the view is not in a hierarchy
        // yet — so the callback is deferred by one turn of the run loop.
        DispatchQueue.main.async { [weak view] in
            if let window = view?.window { onWindowAvailable(window) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in
            if let window = nsView?.window { onWindowAvailable(window) }
        }
    }
}

extension View {
    /// Keeps every window hosting this view out of screen capture while the
    /// exclusion is on.
    func windowCaptureExclusion(_ exclusion: WindowCaptureExclusion) -> some View {
        background(
            WindowAccessor { _ in exclusion.apply() }
                .frame(width: 0, height: 0)
        )
    }
}

#else

/// On iOS the window does not need excluding: the screen *can* be asked whether
/// it is being captured, so the app reacts instead (see `ScreenCaptureMonitor`
/// and `PrivacyShield`). This exists so the app can wire one setting to the same
/// modifier on both platforms without a platform branch at the call site.
@MainActor
final class WindowCaptureExclusion: ObservableObject {
    @Published private(set) var isExcluding = false

    func setExcluding(_ excluding: Bool) {
        isExcluding = excluding
    }

    func apply() {}
}

extension View {
    func windowCaptureExclusion(_ exclusion: WindowCaptureExclusion) -> some View {
        self
    }
}
#endif

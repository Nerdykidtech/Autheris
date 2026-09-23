import SwiftUI

#if os(iOS)
import UIKit
#endif

/// Answers "does this app have room to spread out?" once, in one place, for the
/// few layout decisions that actually depend on it.
///
/// The idiom is asked for rather than the horizontal size class on purpose. A
/// size class changes while the app is running — rotating a large iPhone, or
/// resizing an iPad in Split View or Stage Manager — and any `if` in a view's
/// body that depends on one makes SwiftUI tear down and rebuild the view it
/// wraps, losing its state (search text, an open sheet). An idiom is fixed for
/// the lifetime of the process, so a branch on it never flips.
///
/// A Mac answers `true` for the same reason an iPad does: it has a large display
/// and a pointer, so the roomy layout is the right one. It also happens to be
/// fixed for the lifetime of the process on the Mac — a window can be resized,
/// but the app is still a Mac app — so the property above still holds.
enum AdaptiveLayout {
    /// `true` on an iPad or a Mac: a large display that the roomy layout was
    /// designed for.
    static var usesRoomyLayout: Bool {
        #if os(macOS)
        true
        #else
        UIDevice.current.userInterfaceIdiom == .pad
        #endif
    }
}

/// Widths for a single column of content, chosen by what the content is rather
/// than by which device it is running on.
enum ReadableWidth {
    /// Centred text, onboarding pages, and single-control screens.
    static let prose: CGFloat = 520
}

/// Keeps a single column of content readable on an iPad.
///
/// On an iPhone a screen is its content, so there is nothing to decide. On an
/// iPad the same content would otherwise stretch across the whole display — a
/// paragraph of text running the width of a sheet of paper, or an import summary
/// as wide as the screen — which reads as a phone app someone stretched rather
/// than an app that belongs on the tablet.
///
/// The token list is not one of these: it lays out as a grid of its own, sized by
/// `TokenGrid`.
private struct ReadableWidthModifier: ViewModifier {
    let maxWidth: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        // Gated on the device rather than on width: an iPad in a narrow Split
        // View — or a Mac window dragged narrow — is already narrower than the
        // cap, so gating on the device costs nothing there — while gating on
        // width would also catch a large iPhone in landscape, which is wider
        // than the cap, and quietly change an iPhone layout that this work was
        // not meant to touch.
        if AdaptiveLayout.usesRoomyLayout {
            content.frame(maxWidth: maxWidth)
        } else {
            content
        }
    }
}

extension View {
    /// On iPad, caps one column of content at `maxWidth` points and centres it.
    /// On iPhone the content is left untouched.
    func readableWidth(_ maxWidth: CGFloat) -> some View {
        modifier(ReadableWidthModifier(maxWidth: maxWidth))
    }
}

import SwiftUI

#if os(iOS)
import UIKit

/// The system share sheet.
///
/// One type rather than the two near-identical `UIViewControllerRepresentable`
/// wrappers this app used to carry — a `UIActivityViewController` on iOS and an
/// `NSSharingServicePicker` on the Mac, which is the same feature under each
/// platform's own name. The iOS behaviour is unchanged: it is the same
/// `UIActivityViewController(activityItems:)` call as before.
struct PlatformShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#else
import AppKit

/// `NSSharingServicePicker`, which unlike its iOS counterpart is a *popover*
/// anchored to a view rather than a full-screen controller, so it has to be
/// presented from something already in the hierarchy.
struct PlatformShareSheet: NSViewRepresentable {
    let activityItems: [Any]

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let anchor = NSView(frame: .zero)
        // The picker can only be anchored once the view is in a window, which it
        // is not during `makeNSView`.
        DispatchQueue.main.async {
            // The picker can only be anchored to a view that is in a window.
            guard anchor.window != nil else { return }
            let picker = NSSharingServicePicker(items: activityItems)
            // Retained for as long as the popover is up; the picker is not held
            // by the presentation itself.
            context.coordinator.picker = picker
            picker.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        }
        return anchor
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class Coordinator {
        var picker: NSSharingServicePicker?
    }
}
#endif

import SwiftUI

extension View {
    /// Offers `items` to the system's sharing services while `isPresented` is true.
    ///
    /// The two platforms present this differently, so the difference lives here
    /// rather than at each call site. iOS shows a `UIActivityViewController` in a
    /// sheet, as it always has. The Mac's `NSSharingServicePicker` is a popover
    /// anchored to a view; hosting it in a sheet left an empty, zero-sized sheet
    /// with no way to close it once the picker went away. So on the Mac the picker
    /// is anchored to this view instead, and `isPresented` is reset when it closes.
    func platformShareSheet(isPresented: Binding<Bool>, items: [Any]) -> some View {
        #if os(iOS)
        sheet(isPresented: isPresented) {
            if items.isEmpty {
                Text("Nothing to share.")
                    .platformSheetDetents([.medium])
                    .platformSheetSize(minHeight: 200)
            } else {
                PlatformShareSheet(activityItems: items)
            }
        }
        #else
        background(SharingPickerAnchor(isPresented: isPresented, items: items))
        #endif
    }
}

#if os(iOS)
import UIKit

/// The system share sheet. Presented through `platformShareSheet(isPresented:items:)`.
struct PlatformShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#else
import AppKit

/// Shows `NSSharingServicePicker` from the view it sits behind whenever
/// `isPresented` turns true, and turns it back off when the picker closes —
/// whether a service was chosen or not.
private struct SharingPickerAnchor: NSViewRepresentable {
    @Binding var isPresented: Bool
    let items: [Any]

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ view: NSView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onClose = { isPresented = false }
        guard isPresented, !coordinator.isShowing else { return }
        coordinator.isShowing = true
        // Deferred a turn: the picker can only be anchored to a view that is in a
        // window, and SwiftUI may still be placing this one.
        DispatchQueue.main.async {
            guard view.window != nil, !items.isEmpty else {
                coordinator.close()
                return
            }
            let picker = NSSharingServicePicker(items: items)
            picker.delegate = coordinator
            // Retained while the popover is up; the presentation does not hold it.
            coordinator.picker = picker
            picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        }
    }

    final class Coordinator: NSObject, NSSharingServicePickerDelegate {
        var picker: NSSharingServicePicker?
        var isShowing = false
        var onClose: (() -> Void)?

        func close() {
            picker = nil
            isShowing = false
            onClose?()
        }

        /// Called with `nil` when the picker is dismissed without a choice, so this
        /// is the one place the presentation ends.
        func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker,
                                  didChoose service: NSSharingService?) {
            close()
        }
    }
}
#endif

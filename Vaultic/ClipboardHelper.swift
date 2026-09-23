import Foundation

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Copies sensitive values (codes and secrets) to the pasteboard without
/// Universal Clipboard handoff, so they don't linger on the clipboard or appear
/// on nearby devices.
///
/// The two platforms spell both halves of that differently. iOS has an
/// expiring, local-only pasteboard item; AppKit has neither, so the Mac marks
/// the contents concealed and schedules the clear itself.
enum ClipboardHelper {

    /// Copy `text`, and clear it again once `expiration` has passed.
    static func copy(_ text: String, expiration: TimeInterval = 60) {
        #if os(macOS)
        copyOnMac(text, expiration: expiration)
        #else
        UIPasteboard.general.setItems(
            [["public.utf8-plain-text": text]],
            options: [
                .expirationDate: Date().addingTimeInterval(expiration),
                .localOnly: true
            ]
        )
        #endif
    }

    #if os(macOS)
    /// The timer behind the current copy, so a second copy replaces the first
    /// instead of racing it.
    private static var pendingClear: Task<Void, Never>?

    private static func copyOnMac(_ text: String, expiration: TimeInterval) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // `org.nspasteboard.ConcealedType` is how a Mac app marks pasteboard
        // contents as secret — the same convention the password managers use.
        // Marking it keeps the value out of Universal Clipboard, so a copied code
        // does not turn up on the user's iPhone, and out of clipboard-history
        // tools. That is the Mac spelling of iOS's `.localOnly`. The payload is
        // irrelevant; the type being present is the signal.
        pasteboard.setData(
            Data([0]),
            forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        )

        // Clear only if nothing else has been copied in the meantime: the user
        // copying something of their own should not have it wiped from under
        // them by a timer that was started for a code.
        let changeCount = pasteboard.changeCount
        pendingClear?.cancel()
        pendingClear = Task {
            try? await Task.sleep(for: .seconds(expiration))
            guard !Task.isCancelled,
                  NSPasteboard.general.changeCount == changeCount else { return }
            NSPasteboard.general.clearContents()
        }
    }
    #endif
}

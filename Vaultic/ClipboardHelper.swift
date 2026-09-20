import UIKit

/// Copies sensitive values (codes and secrets) to the pasteboard with an
/// expiration date and without Universal Clipboard handoff, so they don't
/// linger on the clipboard or appear on nearby devices.
enum ClipboardHelper {
    static func copy(_ text: String, expiration: TimeInterval = 60) {
        UIPasteboard.general.setItems(
            [["public.utf8-plain-text": text]],
            options: [
                .expirationDate: Date().addingTimeInterval(expiration),
                .localOnly: true
            ]
        )
    }
}

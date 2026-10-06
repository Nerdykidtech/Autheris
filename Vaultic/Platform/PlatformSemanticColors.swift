#if os(macOS)
import AppKit

/// AppKit spellings for the iOS semantic colours the views already name.
///
/// `Color(.systemBackground)`, `Color(.separator)` and friends are `UIColor`
/// lookups on iOS — AppKit has no `systemBackground` at all, so without these the
/// sixteen call sites that use them simply would not compile on the Mac.
///
/// Adding the *names* rather than rewriting the call sites is deliberate: the
/// colours stay a single lookup with the same meaning on both platforms, and the
/// iOS rendering is untouched because none of this is compiled there.
///
/// Each maps to the AppKit semantic colour that means the same thing, so both
/// appearance modes and the system's own contrast settings are still honoured.
extension NSColor {
    /// The window's own background.
    static var systemBackground: NSColor { .windowBackgroundColor }

    /// A surface *inside* the window — a card, a code field, an input row.
    static var secondarySystemBackground: NSColor { .controlBackgroundColor }

    /// Behind a grouped list's cards, which on the Mac is the window itself.
    static var systemGroupedBackground: NSColor { .windowBackgroundColor }

    /// The card background in a grouped list, which on the Mac is the same
    /// surface as `secondarySystemBackground`.
    static var secondarySystemGroupedBackground: NSColor { .controlBackgroundColor }

    /// Hairline rules between rows and around cards.
    static var separator: NSColor { .separatorColor }
}
#endif

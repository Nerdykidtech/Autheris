import SwiftUI

/// Navigation and presentation spellings that differ between the platforms.
///
/// These are the modifiers iOS has and macOS does not. Each one keeps its iOS
/// meaning exactly as it was, and does the closest honest Mac equivalent rather
/// than being dropped: a Mac sheet still gets sized, and a full-screen cover
/// still presents — just as a sheet, because a Mac window *is* the presentation.
extension View {

    // MARK: - Titles

    /// A compact title inside a pushed screen. The Mac draws navigation titles
    /// in the window toolbar, where there is nothing to make inline.
    @ViewBuilder
    func inlineNavigationTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// The scrolling large title on the token list.
    @ViewBuilder
    func largeNavigationTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.large)
        #else
        self
        #endif
    }

    // MARK: - Presentation

    /// Sizes a sheet on macOS.
    ///
    /// ## Every Mac sheet must carry this
    ///
    /// A macOS sheet has no size of its own. Without an explicit frame the content
    /// is not clipped and not scrolled — it has nothing to lay out into, so the
    /// sheet collapses to an empty box showing only its toolbar. That failure is
    /// silent and looks like a broken view rather than a missing size, which is
    /// exactly how three of this app's sheets shipped without it.
    ///
    /// Deliberately a **no-op on iOS**, which has sizing of its own. Detents are a
    /// separate concern with a separate shim (`platformSheetDetents`), because
    /// folding them in here silently gave sheets that never had detents a
    /// half-height presentation on iPad.
    @ViewBuilder
    func platformSheetSize(minWidth: CGFloat = 460, minHeight: CGFloat = 480) -> some View {
        #if os(macOS)
        self.frame(minWidth: minWidth, minHeight: minHeight)
        #else
        self
        #endif
    }

    /// The sheet's detents, and whether it shows a drag indicator.
    ///
    /// iOS only — `presentationDetents` does not exist on macOS, where a sheet is
    /// sized with `platformSheetSize` instead. Pass exactly the detents the view
    /// had before, rather than assuming a default: a sheet offering `[.medium,
    /// .large]` *opens at the smaller one*, so adding them where they were absent
    /// changes how a screen presents.
    @ViewBuilder
    func platformSheetDetents(
        _ detents: Set<PresentationDetent> = [.medium, .large],
        dragIndicator: Bool = false
    ) -> some View {
        #if os(iOS)
        self
            .presentationDetents(detents)
            .presentationDragIndicator(dragIndicator ? .visible : .automatic)
        #else
        self
        #endif
    }

    /// `fullScreenCover` on iOS; a sheet on macOS.
    ///
    /// A Mac window has no full-screen *presentation* to cover — Settings opens
    /// as its own window-like sheet over the token list, which is the Mac idiom
    /// and keeps the list's state alive behind it.
    @ViewBuilder
    func platformFullScreenCover<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        #if os(iOS)
        self.fullScreenCover(isPresented: isPresented, content: content)
        #else
        self.sheet(isPresented: isPresented, content: content)
        #endif
    }

    // MARK: - Search

    /// The token list's search field.
    ///
    /// iOS pins it under the (large) navigation title and keeps it on screen at
    /// all times. The Mac puts search in the window toolbar, where "always
    /// displayed" is the only behaviour it has — so the placement is simply left
    /// to the platform.
    @ViewBuilder
    func platformSearchable(text: Binding<String>, prompt: LocalizedStringKey) -> some View {
        #if os(iOS)
        self.searchable(
            text: text,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: prompt
        )
        #else
        self.searchable(text: text, prompt: prompt)
        #endif
    }

    // MARK: - Lists

    /// The inset grouped list style, which macOS calls `.inset`.
    @ViewBuilder
    func platformInsetGroupedList() -> some View {
        #if os(iOS)
        self.listStyle(.insetGrouped)
        #else
        self.listStyle(.inset)
        #endif
    }

    // MARK: - Text entry

    /// Restricts a keyboard to ASCII. A Mac has a physical keyboard, so there is
    /// nothing to configure.
    @ViewBuilder
    func asciiCapableKeyboard() -> some View {
        #if os(iOS)
        self.keyboardType(.asciiCapable)
        #else
        self
        #endif
    }

    /// Turns off sentence-style auto-capitalisation for a text field.
    ///
    /// A setup key or an account name must not be capitalised. iOS can be told
    /// so; macOS has no software keyboard to configure and no such modifier, so
    /// there is nothing to turn off.
    @ViewBuilder
    func platformNoAutocapitalization() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.never)
        #else
        self
        #endif
    }

    /// Marks a field that holds a token's setup key as *not* a password.
    ///
    /// A `SecureField` beside an account field is what iOS AutoFill takes for a
    /// login form, and tagging the two `.username` and `.password` — which these
    /// fields used to be — makes certain of it: AutoFill offers a saved password
    /// *into* the setup-key field, and can offer to save the setup key to the
    /// Passwords app on the way out, which would put a secret that is kept
    /// `ThisDeviceOnly` into iCloud Keychain. `.oneTimeCode` is the hint that
    /// keeps password AutoFill away, and it is what the field holds in spirit.
    ///
    /// macOS has no equivalent AutoFill for these fields, so it is a no-op there.
    @ViewBuilder
    func platformSetupKeyContentType() -> some View {
        #if os(iOS)
        self.textContentType(.oneTimeCode)
        #else
        self
        #endif
    }

    // MARK: - Buttons

    /// Widens a control's hit shape to its whole row.
    ///
    /// A macOS `Button` is only hittable where its label *draws*. `.buttonStyle(.plain)`
    /// removes the chrome that used to fill the row, so a settings row styled that way
    /// stopped responding to clicks anywhere except directly on its icon and text —
    /// clicking the empty white space in the middle of the row did nothing. This puts
    /// the hit shape back to the full width.
    ///
    /// A no-op on iOS, where a `List` row is tappable across its width already.
    @ViewBuilder
    func platformActionRowHitArea() -> some View {
        #if os(macOS)
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        #else
        self
        #endif
    }

    /// Tints a `Toggle` with the app's accent colour.
    ///
    /// iOS has no default tint for a switch, so the app supplies one. macOS does:
    /// its switches are system blue, and overriding that is a large part of why the
    /// Mac settings toggles looked like they belonged to another platform. On macOS
    /// this therefore does nothing and the system tint stands.
    @ViewBuilder
    func platformAccentToggle() -> some View {
        #if os(iOS)
        self.toggleStyle(SwitchToggleStyle(tint: .accentColor))
        #else
        self
        #endif
    }

    /// Draws only the button's own content, with no platform chrome.
    ///
    /// Every styled button in this app paints itself — a `Capsule`, a filled row —
    /// which is all iOS displays anyway, so on iOS this is deliberately a no-op and
    /// the shipped appearance is untouched. macOS additionally wraps a plain
    /// `Button` in its default bordered chrome, which drew a *second*, lighter
    /// rounded rectangle around the Capsule: the "overlay around the buttons" on
    /// the Add Token sheet. The tell was a sibling `PhotosPicker` in the same row
    /// that already carried `.buttonStyle(.plain)` and rendered correctly.
    @ViewBuilder
    func platformPlainButton() -> some View {
        #if os(macOS)
        self.buttonStyle(.plain)
        #else
        self
        #endif
    }
}

/// A row of colour swatches.
///
/// On iOS the row scrolls horizontally, because a phone can overflow it and there
/// is a gesture for that. A Mac has no touch scrolling, so an overflowing row
/// there simply looks cut off — and at the preferences window's fixed width the
/// swatches all fit, so they are laid out directly instead.
struct PlatformSwatchRow<Content: View>: View {
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        #if os(iOS)
        ScrollView(.horizontal, showsIndicators: false) {
            row
        }
        #else
        row
        #endif
    }

    private var row: some View {
        HStack(spacing: 14) { content() }
            .padding(.vertical, 4)
    }
}

extension ToolbarItemPlacement {
    // MARK: - Window toolbars

    /// The trailing navigation bar item on iOS; the primary action on the Mac,
    /// where it lands in the window's own toolbar.
    ///
    /// For the main window's controls only. A *modal* needs
    /// `platformSheetTrailing` — see the note there for why the two cannot share
    /// one mapping.
    static var platformTrailing: ToolbarItemPlacement {
        #if os(macOS)
        .primaryAction
        #else
        .navigationBarTrailing
        #endif
    }

    /// The leading navigation bar item on iOS; the leading navigation item on
    /// the Mac, which is `navigation` rather than a bar placement.
    ///
    /// Window toolbars only, like `platformTrailing`.
    static var platformLeading: ToolbarItemPlacement {
        #if os(macOS)
        .navigation
        #else
        .navigationBarLeading
        #endif
    }

    // MARK: - Modal (sheet) toolbars

    /// A modal's leading item — its Cancel button.
    ///
    /// The two platforms cannot share a placement here. `.navigation` puts an
    /// item in the ***window's*** toolbar, and a sheet is not the window: on macOS
    /// a sheet has no `NSToolbar` at all, so the item was dropped silently and the
    /// sheet had no way to be dismissed — not by button, and not by clicking
    /// outside, which sheets do not honour. `cancellationAction` is the placement
    /// SwiftUI renders into a modal's own title area.
    ///
    /// iOS keeps the navigation-bar placement it has always shipped, so nothing
    /// about the released appearance changes.
    static var platformSheetLeading: ToolbarItemPlacement {
        #if os(macOS)
        .cancellationAction
        #else
        .navigationBarLeading
        #endif
    }

    /// A modal's trailing item — its Done button. The counterpart to
    /// `platformSheetLeading`, and needed for the same reason: `.primaryAction` is
    /// a window-toolbar placement and does not appear in a sheet.
    static var platformSheetTrailing: ToolbarItemPlacement {
        #if os(macOS)
        .confirmationAction
        #else
        .navigationBarTrailing
        #endif
    }
}

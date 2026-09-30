import SwiftUI
import Foundation
import Combine
#if os(iOS)
import UIKit
#else
import AppKit
#endif

struct HomeView: View {
    @EnvironmentObject private var dataStore: OTPDataStore
    #if os(macOS)
    /// Opens the Mac's `Settings` scene — the preferences window — which is what
    /// the gear button does there. On iOS/iPad the gear opens the sheet instead.
    @Environment(\.openSettings) private var openSettings
    #endif
    /// Whether the grid is in its rearranging mode — the state `Edit` and `Done`
    /// switch on the iPad, where the grid is not a `List` and so has no edit mode
    /// of its own to inherit.
    @State private var isRearrangingGrid = false
    @State private var showingAddToken = false
    @State private var importResult: (title: String, body: String)? = nil
    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var searchText = ""
    @State private var showingSettings = false
    
    /// The codes to show, in display order.
    ///
    /// `orderedCodes` already applies pinned-first ordering and de-duplication
    /// (SwiftUI's `List` diffing asserts when two rows share an id), so this only
    /// narrows by the search term.
    var filteredCodes: [OTPCode] {
        let ordered = dataStore.orderedCodes
        guard !searchText.isEmpty else { return ordered }

        return ordered.filter { code in
            code.label.localizedCaseInsensitiveContains(searchText) ||
            code.account.localizedCaseInsensitiveContains(searchText)
        }
    }

    /// Reordering a filtered list cannot be mapped back onto the stored order, so
    /// dragging is only offered while the whole list is on screen.
    private var canReorder: Bool {
        searchText.isEmpty && !filteredCodes.isEmpty
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            if searchText.isEmpty {
                Image(systemName: "lock.shield")
                    .font(.system(size: 40))
                    .foregroundColor(.accentColor)
                    .opacity(0.5)

                Text("No Tokens Yet")
                    .font(.headline)
                    .foregroundColor(.secondary)

                Text("Add your first authentication token to get started")
                    .font(.subheadline)
                    .foregroundColor(.secondary.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            } else {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary)
                    .opacity(0.5)

                Text("No Results")
                    .font(.headline)
                    .foregroundColor(.secondary)

                Text("No tokens match \"\(searchText)\"")
                    .font(.subheadline)
                    .foregroundColor(.secondary.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    var body: some View {
        // Settings is a full-screen hub on iPhone: it takes over the display and
        // carries its own Done button. Doing the same on an iPad is heavier than
        // the platform asks of a modal, so there it opens as a sheet, at the
        // system's form-sheet size.
        if AdaptiveLayout.usesRoomyLayout {
            #if os(macOS)
            // The Mac has no settings sheet: the gear button and ⌘, open the
            // `Settings` scene instead. See `AutherisApp`.
            tokenList
            #else
            tokenList.sheet(isPresented: $showingSettings) {
                SettingsView(dataStore: dataStore)
            }
            #endif
        } else {
            tokenList.platformFullScreenCover(isPresented: $showingSettings) {
                SettingsView(dataStore: dataStore)
            }
        }
    }

    /// The iPad grid: two cards per row, in a `ScrollView` rather than a `List`.
    ///
    /// `List` is what makes the one-column list reorderable, but its drag moves a
    /// whole row — and in a grid a row is two codes. So the grid does its own
    /// dragging, one card at a time.
    private func cardGrid(columns: Int, rearranging: Bool) -> some View {
        ScrollView {
            TokenGridView(codes: filteredCodes, columns: columns, rearranging: rearranging)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .readableWidth(TokenGrid.maximumContentWidth)
    }

    /// The list as it has always been: one card per row, reordered by `List`'s own
    /// drag — which moves exactly one code, because a row is one code.
    private func singleColumnList() -> some View {
        List {
            ForEach(filteredCodes) { code in
                OTPCardView(code: code, dataStore: dataStore)
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .onMove { offsets, destination in
                dataStore.move(offsets: offsets, destination: destination)
            }
            .moveDisabled(!canReorder)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    /// How many cards fit across, once the grid is capped at the width it draws in.
    private func columns(forWidth width: CGFloat) -> Int {
        TokenGrid.columns(forWidth: min(width, TokenGrid.maximumContentWidth))
    }

    private func isGridLayout(width: CGFloat) -> Bool {
        columns(forWidth: width) > 1
    }

    /// The bar's own contents.
    ///
    /// The reorder control differs by layout, deliberately. `EditButton` drives
    /// the edit mode a `List` provides, and the grid is not a `List` — tapping it
    /// there did nothing at all. The grid therefore has a button and a flag of its
    /// own.
    @ToolbarContentBuilder
    private func toolbarContent(width: CGFloat) -> some ToolbarContent {
        ToolbarItem(placement: .platformLeading) {
            Button {
                #if os(macOS)
                // On the Mac, Settings is a preferences window (⌘,), not a sheet.
                // `openSettings` can leave the window behind the main one when the
                // app is not already active, so it is brought forward explicitly.
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
                #else
                showingSettings = true
                #endif
            } label: {
                Image(systemName: "gear")
                    .font(.title3)
            }
        }

        ToolbarItemGroup(placement: .platformTrailing) {
            // Reordering is hidden while a search is active, which avoids a mode
            // that would offer nothing to rearrange.
            if canReorder {
                if isGridLayout(width: width) {
                    Button(isRearrangingGrid ? "Done" : "Edit") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isRearrangingGrid.toggle()
                        }
                    }
                } else {
                    // `EditButton` drives the edit mode a `List` provides, and
                    // macOS has neither the control nor the mode: a Mac list is
                    // reordered by dragging a row directly, with no mode to enter
                    // first. So the Mac simply has no control here — nothing is
                    // lost, because the drag works without one.
                    #if os(iOS)
                    EditButton()
                    #endif
                }
            }

            // Add token button on the right (standard iOS pattern)
            Button(action: {
                showingAddToken = true
            }) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundColor(.accentColor)
            }
        }
    }

    private var tokenList: some View {
        NavigationStack {
            // The width decides the layout: two cards across, or the one-column
            // list. The grid caps and centres itself, and the toolbar needs the
            // same answer, so it is built in here too.
            GeometryReader { proxy in
                Group {
                    if filteredCodes.isEmpty {
                        emptyState
                    } else if isGridLayout(width: proxy.size.width) {
                        cardGrid(columns: columns(forWidth: proxy.size.width),
                                 rearranging: isRearrangingGrid && canReorder)
                    } else {
                        singleColumnList()
                    }
                }
                .toolbar { toolbarContent(width: proxy.size.width) }
            }
            .platformSearchable(text: $searchText, prompt: "Search tokens")
            .navigationTitle("Autheris")
            .largeNavigationTitle()
            .sheet(isPresented: $showingAddToken) {
                AddTokenView(dataStore: dataStore, importResult: $importResult)
                    .platformSheetDetents(dragIndicator: true)
            .platformSheetSize()
            }
            .alert(
                Text(importResult?.title ?? "Import"),
                isPresented: Binding(
                    get: { importResult != nil },
                    set: { if !$0 { importResult = nil } }
                ),
                presenting: importResult
            ) { _ in
                Button("OK") { importResult = nil }
            } message: { result in
                Text(result.body)
            }
            .onReceive(timer) { _ in
                // Force view update every second for countdown
            }
        }
    }
}

/// The iPad grid of cards, and the drag that rearranges it.
///
/// While the grid is being rearranged each card carries the same reorder control
/// `List` draws on an iPhone row, and the grid rearranges *under the finger*: as a
/// carried card passes over another slot, the codes around it move out of the way,
/// and letting go settles it into place. That is the iPhone behaviour, at one card
/// per gesture rather than one row.
private struct TokenGridView: View {
    let codes: [OTPCode]
    let columns: Int
    let rearranging: Bool

    @EnvironmentObject private var dataStore: OTPDataStore

    /// The grid's own coordinate space. A drag is measured against the grid rather
    /// than against the card it started on, so a card's offset can be computed from
    /// where its slot is — which changes as the grid rearranges.
    static let coordinateSpace = "tokenGrid"

    /// The card under the finger.
    @State private var draggedID: UUID?
    /// Where the finger is, in `coordinateSpace`.
    @State private var finger: CGPoint = .zero
    /// Where on the card the finger took hold, so picking it up does not make it jump.
    @State private var grabOffset: CGSize = .zero
    /// The size of one cell, measured from the first card that reports it. Every
    /// cell is the same size, which is what makes the slot maths exact.
    @State private var cellSize: CGSize = .zero

    private var spacing: CGFloat { TokenGrid.cardSpacing }

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: columns),
            spacing: spacing
        ) {
            ForEach(codes) { code in
                cell(code)
            }
        }
        .coordinateSpace(name: Self.coordinateSpace)
    }

    private func cell(_ code: OTPCode) -> some View {
        let isDragged = draggedID == code.id

        return OTPCardView(code: code, dataStore: dataStore, isRearranging: rearranging)
            .overlay(alignment: .trailing) {
                if rearranging {
                    grabber(for: code)
                }
            }
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { size in
                if cellSize != size { cellSize = size }
            }
            .scaleEffect(isDragged ? 1.04 : 1)
            .shadow(color: .black.opacity(isDragged ? 0.18 : 0),
                    radius: isDragged ? 14 : 0,
                    y: isDragged ? 8 : 0)
            .offset(isDragged ? offsetOfDraggedCard() : .zero)
            .transaction { transaction in
                // The carried card has to track the finger exactly, so its own
                // movement is never animated — while everything it displaces is.
                if isDragged { transaction.animation = nil }
            }
            .zIndex(isDragged ? 1 : 0)
    }

    /// The reorder control — the same grabber `List` draws on an iPhone row.
    ///
    /// The drag is offered here and nowhere else, so a finger on the rest of a card
    /// still scrolls the grid.
    private func grabber(for code: OTPCode) -> some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 36, height: 44)
            .contentShape(Rectangle())
            .padding(.trailing, 2)
            .gesture(dragToReorder(code))
            .accessibilityLabel("Reorder \(code.label)")
    }

    private func dragToReorder(_ code: OTPCode) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.coordinateSpace))
            .onChanged { value in
                if draggedID != code.id, let index = currentIndex(of: code.id) {
                    // Picked up. Remember where the finger is on the card so it
                    // carries on from there rather than snapping to the centre.
                    draggedID = code.id
                    let origin = origin(ofIndex: index)
                    grabOffset = CGSize(width: value.startLocation.x - origin.x,
                                        height: value.startLocation.y - origin.y)
                }

                finger = value.location

                let slot = TokenGrid.slotIndex(at: value.location,
                                               cellSize: cellSize,
                                               columns: columns,
                                               spacing: spacing,
                                               count: codes.count)
                if let current = currentIndex(of: code.id), current != slot {
                    let destination = TokenGrid.insertionIndex(hoveringSlot: slot,
                                                               liftedFrom: current)
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                        dataStore.moveCode(withID: code.id, toDisplayedIndex: destination)
                    }
                }
            }
            .onEnded { _ in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    draggedID = nil
                }
            }
    }

    // MARK: - Grid geometry

    private func currentIndex(of id: UUID) -> Int? {
        codes.firstIndex { $0.id == id }
    }

    /// The top-left of the slot at `index`, in `coordinateSpace`.
    private func origin(ofIndex index: Int) -> CGPoint {
        CGPoint(
            x: CGFloat(index % columns) * (cellSize.width + spacing),
            y: CGFloat(index / columns) * (cellSize.height + spacing)
        )
    }

    /// How far the carried card is drawn from its slot: enough to sit under the
    /// finger, wherever its slot has moved to.
    private func offsetOfDraggedCard() -> CGSize {
        guard let id = draggedID, let index = currentIndex(of: id) else { return .zero }
        let slot = origin(ofIndex: index)
        return CGSize(width: finger.x - grabOffset.width - slot.x,
                      height: finger.y - grabOffset.height - slot.y)
    }
}

struct OTPCardView: View {
    let code: OTPCode
    let dataStore: OTPDataStore
    /// `true` while this card is being rearranged in the iPad grid.
    ///
    /// Tapping it to copy, or holding it for its menu, would then compete with the
    /// drag that is the whole point of the mode, so in it the card answers only to
    /// being picked up.
    var isRearranging: Bool = false
    
    @State private var remainingSeconds: Int = 30
    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var isCopied = false
    @State private var showEditSheet = false
    @State private var showSecretSheet = false
    
    // Compute warning threshold based on period
    private var warningThreshold: Int {
        return max(5, Int(Double(code.effectivePeriod) * 0.1667)) // 5 seconds or 1/6 of period
    }

    private var branding: IssuerBranding {
        IssuerBranding.forLabel(code.label)
    }
    
    private var timerRingColor: Color {
        if let hex = code.timerRingHex, let c = Color(hex: hex) {
            return c
        }
        return branding.color
    }

    private var isExpiring: Bool {
        // Only a time-based code expires. A counter-based one is spent by use, so
        // there is no moment at which it is about to stop working and nothing for
        // the red state to mean.
        code.isTimeBased && remainingSeconds <= warningThreshold
    }

    private var countdownProgress: Double {
        // `effectivePeriod` is always positive, so this cannot divide by zero even
        // for a token whose stored period is malformed.
        return min(max(Double(remainingSeconds) / Double(code.effectivePeriod), 0), 1)
    }

    // MARK: - Sizing

    /// The card is drawn at iPhone size by default and given a little more room in
    /// the roomy grid, where it fills a wider column and is read from further away.
    private var iconSize: CGFloat { AdaptiveLayout.usesRoomyLayout ? 44 : 40 }
    private var codeTextStyle: Font.TextStyle { AdaptiveLayout.usesRoomyLayout ? .title : .title2 }
    private var countdownWidth: CGFloat { AdaptiveLayout.usesRoomyLayout ? 84 : 56 }
    private var verticalPadding: CGFloat { AdaptiveLayout.usesRoomyLayout ? 14 : 12 }

    var body: some View {
        card
            .sheet(isPresented: $showEditSheet) {
                EditTokenView(code: code, dataStore: dataStore)
            }
            .sheet(isPresented: $showSecretSheet) {
                TokenSecretView(code: code, dataStore: dataStore)
            }
            .onAppear {
                updateRemainingSeconds()
            }
            .onReceive(timer) { _ in
                updateRemainingSeconds()
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isExpiring)
            .animation(.easeInOut(duration: 0.2), value: isCopied)
    }

    /// The card as the user sees it, with the two things that depend on what it is
    /// for: normally tapping copies the code and a long press opens its menu, while
    /// in the grid's rearranging mode it is picked up and dropped instead.
    @ViewBuilder
    private var card: some View {
        if isRearranging {
            surface
        } else {
            surface
                .onTapGesture {
                    // Tap to copy with haptic feedback
                    copyToClipboard()
                }
                .contextMenu {
                    Button {
                        dataStore.setPinned(!code.isPinned, for: code)
                    } label: {
                        Label(code.isPinned ? "Unpin" : "Pin",
                              systemImage: code.isPinned ? "pin.slash" : "pin")
                    }

                    // Only for a counter-based code: a time-based one gets its next
                    // code from the clock, and there is nothing to ask for.
                    if !code.isTimeBased {
                        Button {
                            Haptics.impact(.light)
                            dataStore.advanceCounter(for: code)
                        } label: {
                            Label("Next Code", systemImage: "arrow.clockwise")
                        }
                    }

                    Button {
                        copyToClipboard()
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }

                    Button {
                        showSecretSheet = true
                    } label: {
                        Label("View Secret", systemImage: "key")
                    }

                    Button {
                        showEditSheet = true
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }

                    Button(role: .destructive) {
                        // Haptic feedback for delete action
                        Haptics.notify(.warning)
                        deleteToken()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
        }
    }

    private var surface: some View {
        HStack(spacing: 12) {
            IssuerIconView(branding: branding, size: iconSize)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    if code.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundColor(.accentColor)
                    }

                    Text(code.label)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    code.isPinned
                        ? String(localized: "\(code.label), pinned")
                        : code.label
                )

                if !code.account.isEmpty {
                    Text(code.account)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                if isCopied {
                    Label("Copied", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.accentColor)
                } else {
                    Text(code.currentCode)
                        .font(.system(codeTextStyle, design: .monospaced).weight(.bold))
                        .foregroundColor(isExpiring ? .red : .primary)
                }

                if code.isTimeBased {
                    HStack(spacing: 6) {
                        ProgressView(value: countdownProgress)
                            .frame(width: countdownWidth)
                            .tint(isExpiring ? .red : timerRingColor)

                        Text("\(remainingSeconds)s")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(isExpiring ? .red : .secondary)
                    }
                } else {
                    // A counter-based code has nothing to count down and no colour to
                    // warn with — it is valid until it is spent. What the row offers
                    // instead is the one action such a code has: spending it. The
                    // counter is shown beside it because it is what the service's own
                    // prompt may quote back, and the two together are how a user tells
                    // which code is on screen.
                    //
                    // Deliberately *not* wired to the card's tap. Tapping the card
                    // copies, and a copy is not proof the service accepted the code —
                    // spending a counter on a copy would take away a code the user
                    // may still need to retype.
                    HStack(spacing: 8) {
                        // `Int` rather than the model's `UInt64` so the catalog key is
                        // `Counter %lld`, like every other number in it; the value is
                        // bounded by `OTPCode.maximumCounter`, so the conversion is
                        // lossless.
                        Text("Counter \(Int(clamping: code.counter))")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                            // Fixed rather than flexible. This column shares the row
                            // with the service name, and a squeezable label here is
                            // what wrapped "Counter" onto two lines and stretched the
                            // button into a tall lozenge — the name is the thing that
                            // is *meant* to give way, and its own `lineLimit(1)`
                            // already says so.
                            .lineLimit(1)
                            .fixedSize()

                        // Painted rather than left to `.bordered`, which drew a grey,
                        // full-weight system capsule: the loudest thing on a card whose
                        // whole design is the app's own colour. This is the app's
                        // action colour instead — the same tint as the "Copied" label
                        // that appears here in its place, and as the toolbar above it.
                        //
                        // Deliberately not the issuer's colour, which the card already
                        // wears on its icon: a brand tint that happens to be pale (an
                        // amber, say) leaves the label unreadable on its own 15% fill,
                        // and a *control* is not the place to be tasteful about that.
                        Button {
                            Haptics.impact(.light)
                            dataStore.advanceCounter(for: code)
                        } label: {
                            Label("Next", systemImage: "arrow.clockwise")
                                // Pinned: left to itself, `Label` drops its title when
                                // the proposed width is tight — which is this column —
                                // and renders the icon alone inside a capsule sized for
                                // both, so the chip looked empty and off-centre.
                                .labelStyle(.titleAndIcon)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.accentColor)
                                .lineLimit(1)
                                .fixedSize()
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                                .contentShape(Capsule())
                                .fixedSize()
                        }
                        // `.plain` on iOS keeps the capsule the only chrome; on macOS
                        // it is what stops the system drawing a second bezel around it.
                        .buttonStyle(.plain)
                        .platformPlainButton()
                        .accessibilityLabel(Text("Next Code"))
                    }
                }
            }
        }
        // Fills the column it is given, so the card's background reaches the edges
        // of its cell in the iPad grid. It was already full width on iPhone, where
        // the row is the display.
        .frame(maxWidth: .infinity)
        .padding(.leading, 16)
        // While rearranging, the card steps in from the trailing edge to leave the
        // reorder grabber its own space.
        .padding(.trailing, isRearranging ? TokenGrid.grabberSpace : 16)
        .padding(.vertical, verticalPadding)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    isExpiring ? Color.red.opacity(0.45) : Color(.separator).opacity(0.15),
                    lineWidth: isExpiring ? 1 : 0.5
                )
        )
    }
    
    private func updateRemainingSeconds() {
        // A counter-based card has no countdown to keep current, and updating the
        // value every second would re-render the card to show the same code.
        guard code.isTimeBased else { return }

        let currentTime = Date().timeIntervalSince1970
        let period = Double(code.effectivePeriod)
        let elapsed = currentTime.truncatingRemainder(dividingBy: period)
        let newRemainingSeconds = Int(period - elapsed)
        
        if newRemainingSeconds != remainingSeconds {
            remainingSeconds = newRemainingSeconds
        }
    }
    
    private func copyToClipboard() {
        // Light haptic feedback for copy
        Haptics.impact(.light)
        
        ClipboardHelper.copy(code.currentCode)
        withAnimation {
            isCopied = true
        }
        
        // Reset after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                isCopied = false
            }
        }
    }
    
    private func deleteToken() {
        dataStore.removeCode(code)
    }
}

struct EditTokenView: View {
    let code: OTPCode
    @ObservedObject var dataStore: OTPDataStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var label: String
    @State private var account: String
    @State private var ringColor: Color
    /// Seeded from the *effective* values, so opening this screen on a token whose
    /// stored digits or period is malformed shows something sane, and saving repairs
    /// it. `OTPGenerator` decides what "effective" means.
    @State private var algorithm: OTPAlgorithm
    @State private var digits: Int
    @State private var period: Int
    /// The counter, as an `Int` because that is what `Stepper` binds to. Kept and
    /// saved only for a counter-based token; see `codeSection`.
    @State private var counter: Int
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var showDiscardConfirmation = false
    
    private var editBranding: IssuerBranding {
        IssuerBranding.forLabel(code.label)
    }
    
    private var isDirty: Bool {
        label != code.label ||
        account != code.account ||
        algorithm != code.algorithm ||
        digits != code.effectiveDigits ||
        period != code.effectivePeriod ||
        counter != Int(clamping: code.counter) ||
        ringHexForSave() != code.timerRingHex
    }
    
    init(code: OTPCode, dataStore: OTPDataStore) {
        self.code = code
        self.dataStore = dataStore
        _label = State(initialValue: code.label)
        _account = State(initialValue: code.account)
        _algorithm = State(initialValue: code.algorithm)
        // Clamped into the ranges the steppers offer, so a malformed stored value
        // opens as a usable one rather than leaving a control out of range.
        _digits = State(initialValue: min(max(code.effectiveDigits, 6), 10))
        _period = State(initialValue: min(max(code.effectivePeriod, 15), 300))
        _counter = State(initialValue: Int(clamping: code.counter))
        let branding = IssuerBranding.forLabel(code.label)
        if let hex = code.timerRingHex, let c = Color(hex: hex) {
            _ringColor = State(initialValue: c)
        } else {
            _ringColor = State(initialValue: branding.color)
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                headerSection
                identitySection
                codeSection
                // A counter-based code has no countdown ring, so a ring colour would
                // be a setting that changes nothing on screen.
                if code.isTimeBased {
                    appearanceSection
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit Token")
            .inlineNavigationTitle()
            .toolbar {
                // `.cancellationAction` / `.confirmationAction` are SwiftUI's own
                // placements for a modal, so the system decides the position and the
                // emphasis of the confirming action rather than me guessing at it.
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if isDirty {
                            showDiscardConfirmation = true
                        } else {
                            dismiss()
                        }
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                    .disabled(!isDirty)
                }
            }
            .interactiveDismissDisabled(isDirty)
            .confirmationDialog(
                "Unsaved Changes",
                isPresented: $showDiscardConfirmation,
                titleVisibility: .visible
            ) {
                Button("Discard Changes", role: .destructive) {
                    dismiss()
                }
                Button("Keep Editing", role: .cancel) { }
            } message: {
                Text("Your edits have not been saved.")
            }
            .alert("Error", isPresented: $showingAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
        }
        .platformSheetDetents(dragIndicator: true)
            .platformSheetSize()
    }

    // MARK: - Sections

    /// Issuer icon and a live code, so the effect of changing the algorithm or the
    /// period is visible immediately — and so a token that produces no code at all
    /// is obvious rather than something to discover later.
    private var headerSection: some View {
        Section {
            HStack(spacing: 14) {
                IssuerIconView(branding: previewBranding, size: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text(label.isEmpty ? code.label : label)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    if !account.isEmpty {
                        Text(account)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                // Ticks, so the preview does not sit frozen on a stale code — unless
                // the code has no clock to tick with, in which case it is redrawn
                // when the counter changes instead.
                if code.isTimeBased {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        previewText
                    }
                } else {
                    previewText
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var identitySection: some View {
        Section {
            TextField("Service name", text: $label)

            TextField("Account (optional)", text: $account)
                .platformTextContentType(.username)
                .platformNoAutocapitalization()
        }
    }

    private var codeSection: some View {
        Section {
            Picker("Algorithm", selection: $algorithm) {
                ForEach(OTPAlgorithm.allCases, id: \.self) { option in
                    Text(option.rawValue).tag(option)
                }
            }

            Stepper("Digits: \(digits)", value: $digits, in: 6...10)

            // A period and a counter are the two halves of "when does this code
            // change", and a token has one of them. The kind itself is not offered
            // here: changing it would turn a working token into one whose codes stop
            // being accepted, with no way to check first — the kind is settled by the
            // QR the service gave you, and a mis-scanned one is better re-added.
            if code.isTimeBased {
                Stepper("Period: \(period) seconds", value: $period, in: 15...300, step: 15)
            } else {
                Stepper("Counter: \(counter)", value: $counter, in: 0...10_000)
            }
        } header: {
            Text("Code")
        } footer: {
            Text(codeFooter)
        }
    }

    /// Typed explicitly: a ternary of two literals infers as `String`, which `Text`
    /// renders verbatim and never looks up — so the string would ship in English in
    /// all seven languages with nothing to notice.
    private var codeFooter: LocalizedStringKey {
        code.isTimeBased
            ? "Scanning a service's QR code fills these in. If your codes are rejected, check the service's instructions — most use SHA-1 and 30 seconds, but some (myGov, for example) need SHA-256."
            : "This code changes only when you ask for the next one. Raise the counter if the service has moved ahead of it — for instance after a code was used on a device that no longer has this account."
    }

    private var appearanceSection: some View {
        Section {
            ColorPicker(selection: $ringColor, supportsOpacity: false) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .stroke(Color(.separator).opacity(0.35), lineWidth: 1)
                            .frame(width: 36, height: 36)
                        Circle()
                            .stroke(ringColor, lineWidth: 3)
                            .frame(width: 28, height: 28)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Ring color")
                        Text(ringColorLabel)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }

            Button("Use service default") {
                ringColor = editBranding.color
            }
            .disabled(ringColorMatchesBranding)
        } header: {
            Text("Appearance")
        }
    }

    /// The icon for what is currently typed, so a rename updates it.
    ///
    /// `editBranding` stays tied to the stored label, because `ringHexForSave` uses
    /// it to decide whether the chosen color counts as "automatic".
    private var previewBranding: IssuerBranding {
        IssuerBranding.forLabel(label.isEmpty ? code.label : label)
    }

    /// What the code would be with the values currently on screen, rather than the
    /// stored ones.
    private var previewCode: String {
        guard code.isTimeBased else {
            return OTPGenerator.generateHOTP(secret: code.secret, algorithm: algorithm,
                                             digits: digits, counter: UInt64(max(0, counter)))
        }
        return OTPGenerator.generateOTP(secret: code.secret, algorithm: algorithm,
                                         digits: digits, period: period)
    }

    private var previewText: some View {
        Text(previewCode)
            .font(.system(.body, design: .monospaced).weight(.semibold))
            .foregroundColor(.secondary)
    }

    private var ringColorMatchesBranding: Bool {
        guard let picked = ringColor.rgbHexStringForStorage(),
              let brand = editBranding.color.rgbHexStringForStorage() else {
            return false
        }
        return picked == brand
    }

    /// Typed explicitly: a ternary of two literals infers as `String`, which
    /// `Text` renders verbatim and never looks up.
    private var ringColorLabel: LocalizedStringKey {
        ringColorMatchesBranding ? "Automatic (service color)" : "Custom color"
    }
    
    /// `nil` when the chosen color matches the automatic service color (same as legacy “default”).
    private func ringHexForSave() -> String? {
        guard let picked = ringColor.rgbHexStringForStorage() else { return code.timerRingHex }
        guard let brand = editBranding.color.rgbHexStringForStorage() else { return picked }
        return picked == brand ? nil : picked
    }
    
    private func saveChanges() {
        if label.isEmpty {
            alertMessage = String(localized: "Service name cannot be empty.")
            showingAlert = true
            return
        }
        
        // Goes through `edited()` rather than rebuilding the token field by field,
        // so a field added later cannot be silently reset by this screen — which is
        // exactly what adding `isPinned` would otherwise have done.
        let updatedCode = code.edited(
            label: label,
            account: account,
            algorithm: algorithm,
            digits: digits,
            period: period,
            counter: UInt64(max(0, counter)),
            timerRingHex: .some(ringHexForSave())
        )
        
        if let index = dataStore.codes.firstIndex(where: { $0.id == code.id }) {
            dataStore.updateCode(updatedCode, at: index)
            // Success haptic feedback
            Haptics.notify(.success)
        }
        
        dismiss()
    }
}

#Preview {
    HomeView()
        .environmentObject(OTPDataStore())
}

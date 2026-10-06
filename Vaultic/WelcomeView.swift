import SwiftUI

/// The first thing a new install shows: what Autheris is, what it does, how it
/// treats your privacy — with the switches that decide it — and a recap.
///
/// The privacy page is the reason for the order. It comes before the first code
/// is added, because one of its switches, service logos, decides whether
/// anything about that code leaves the device. See `OnboardingChoices`.
///
/// Every animation here is decoration, so each one checks Reduce Motion and
/// settles into its final state without moving when it is on.
struct WelcomeView: View {
    @State private var currentPage = 0
    /// Pages whose content has played its entrance, so going back to one
    /// doesn't play it again.
    @State private var revealedPages: Set<Int> = []
    @State private var choices = OnboardingChoices()
    @State private var showingAppLockUnavailable = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Bound straight to Settings' keys: their defaults don't change for a new
    // install, so the page shows and edits exactly what Settings would.
    @AppStorage("enablePrivacyBlur") private var enablePrivacyBlur = true
    @AppStorage("hideCodesInAppSwitcher") private var hideCodesInAppSwitcher = true
    @AppStorage("hideCodesWhenScreenCaptured") private var hideCodesWhenScreenCaptured = true
    @AppStorage(AppLockEnabledKey) private var enableAppLock = false
    @AppStorage(AppPreferences.sendCodesToWatchKey)
    private var sendCodesToWatch = AppPreferences.sendCodesToWatchDefault
    /// Read only: turning sync on needs the account checks Settings makes. It is
    /// shown as it is, because a reinstall can restore it already on.
    @AppStorage(OTPDataStore.syncEnabledKey) private var isICloudSyncEnabled = false
    /// The watch switch and its summary row show only with a paired watch;
    /// without one they would ask about something the user doesn't have.
    /// Settings keeps the switch either way.
    @State private var hasPairedWatch = WatchTokenRelay.hasPairedWatch

    private enum Page: Int, CaseIterable {
        case welcome, features, privacy, ready
    }

    private var isLastPage: Bool { currentPage == Page.allCases.count - 1 }

    /// Typed explicitly: a ternary of two literals infers as `String`, which
    /// `Text` renders verbatim and never looks up.
    private var advanceTitle: LocalizedStringKey {
        isLastPage ? "Get Started" : "Continue"
    }

    var body: some View {
        ZStack {
            OnboardingBackground()

            VStack(spacing: 0) {
                #if os(iOS)
                TabView(selection: $currentPage) {
                    ForEach(Page.allCases, id: \.rawValue) { page in
                        content(for: page).tag(page.rawValue)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxHeight: .infinity)
                #else
                // macOS has no paging container — `.page` is iOS-only, and a
                // plain `TabView` there draws a tab bar. The Back and Continue
                // buttons already drive `currentPage`, so the Mac shows the
                // selected page and cross-fades between them.
                content(for: Page(rawValue: currentPage) ?? .welcome)
                    .id(currentPage)
                    .transition(.opacity)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: currentPage)
                #endif

                VStack(spacing: 20) {
                    pageDots
                    navigationButtons
                }
                .readableWidth(ReadableWidth.prose)
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .task {
            // A beat after the view appears, not as it does: the first frames
            // of a launch are often dropped while the app loads, and the
            // welcome's entrance used to play out unseen behind them.
            if !reduceMotion {
                try? await Task.sleep(for: .milliseconds(450))
            }
            revealedPages.insert(currentPage)
        }
        .onChange(of: currentPage) { _, page in revealedPages.insert(page) }
        .onReceive(NotificationCenter.default.publisher(for: WatchTokenRelay.pairedWatchDidChange)) { _ in
            hasPairedWatch = WatchTokenRelay.hasPairedWatch
        }
        .alert("App Lock Unavailable", isPresented: $showingAppLockUnavailable) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("App Lock needs a passcode or password on this device to unlock Autheris. Set one up, then turn App Lock on again.")
        }
    }

    @ViewBuilder
    private func content(for page: Page) -> some View {
        switch page {
        case .welcome: welcomePage
        case .features: featuresPage
        case .privacy: privacyPage
        case .ready: readyPage
        }
    }

    private func isRevealed(_ page: Page) -> Bool {
        revealedPages.contains(page.rawValue)
    }

    /// Fades and lifts one piece of a page into place, `step` beats after the
    /// page first shows.
    private func reveal(_ page: Page, step: Int) -> RevealModifier {
        RevealModifier(isRevealed: isRevealed(page),
                       delay: 0.15 + 0.08 * Double(step),
                       reduceMotion: reduceMotion)
    }

    // MARK: - Pages

    private var welcomePage: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)

            OrbitHero(isShown: isRevealed(.welcome),
                      animated: !reduceMotion,
                      isOnScreen: currentPage == Page.welcome.rawValue,
                      satellites: ["lock.fill", "key.fill", "faceid"]) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 112, height: 112)
                    .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
                    .shadow(color: Color.accentColor.opacity(0.3), radius: 22, y: 12)
            }

            Spacer(minLength: 12)

            VStack(spacing: 12) {
                Text("Welcome to")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .modifier(reveal(.welcome, step: 2))

                Text("Autheris")
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .modifier(reveal(.welcome, step: 3))

                Text("Two-factor codes that stay yours.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .modifier(reveal(.welcome, step: 4))

                promises
                    .padding(.top, 10)
                    .modifier(reveal(.welcome, step: 5))
            }

            Spacer(minLength: 12)
        }
        .readableWidth(ReadableWidth.prose)
        .padding(.horizontal, 24)
    }

    /// The three promises in one quiet line rather than three buttons-that-
    /// aren't.
    private var promises: some View {
        HStack(spacing: 14) {
            promise("No account", systemImage: "person.crop.circle.badge.xmark")
            promise("No tracking", systemImage: "eye.slash")
            promise("Open source", systemImage: "chevron.left.forwardslash.chevron.right")
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private func promise(_ text: LocalizedStringKey, systemImage: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.accentColor)
                .imageScale(.small)
            Text(text)
        }
    }

    private var featuresPage: some View {
        page(
            .features,
            icon: "sparkles",
            title: "What Autheris Does",
            subtitle: "Everything you need for two-factor sign-in, and nothing you don't."
        ) {
            card {
                featureRow(
                    icon: "qrcode.viewfinder",
                    title: "Add Accounts in Seconds",
                    detail: "Scan a QR code, open a setup link, or bring your codes over from Google Authenticator and other apps."
                )
                cardDivider
                featureRow(
                    icon: "doc.on.doc",
                    title: "Copy with One Tap",
                    detail: "Every code shows how long it has left, so you never paste one that's about to change."
                )
                cardDivider
                featureRow(
                    icon: "macbook.and.iphone",
                    title: "On Your Devices",
                    detail: "iPhone, iPad and Mac stay in step through iCloud Sync if you turn it on. Apple Watch gets your codes from your iPhone."
                )
                cardDivider
                featureRow(
                    icon: "lock.doc",
                    title: "Backups You Control",
                    detail: "Save a password-encrypted backup file, and restore it whenever you need to."
                )
            }
            .modifier(reveal(.features, step: 3))
        }
    }

    private var privacyPage: some View {
        page(
            .privacy,
            icon: "hand.raised.fill",
            title: "Private by Design",
            subtitle: "Autheris has no account, no ads, no analytics and no server of its own. Your setup keys are kept in this device's Keychain, and leave it only in the ways listed below."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("Leaves your device only if you allow it")
                card {
                    switchRow(
                        "Fetch service logos",
                        icon: "photo",
                        detail: "Looks up each service's icon by name at logo.dev, which tells logo.dev which services you use. Your codes and setup keys are never sent. Off, each service shows its first letter.",
                        isOn: $choices.fetchIssuerLogos
                    )
                    if hasPairedWatch {
                        cardDivider
                        switchRow(
                            "Send codes to Apple Watch",
                            icon: "applewatch",
                            detail: "If Autheris is on your Apple Watch, this iPhone copies your codes to it, setup keys included, so the watch can show them. Off, they are removed from the watch.",
                            isOn: $sendCodesToWatch
                        )
                    }
                    cardDivider
                    if isICloudSyncEnabled {
                        featureRow(
                            icon: "icloud",
                            title: "iCloud Sync is on",
                            detail: "Your codes sync through your private iCloud database, and setup keys are end-to-end encrypted. You can turn it off in Settings."
                        )
                    } else {
                        featureRow(
                            icon: "icloud",
                            title: "iCloud Sync is off",
                            detail: "Turn it on in Settings to sync through your private iCloud database. Setup keys are end-to-end encrypted."
                        )
                    }
                }
            }
            .modifier(reveal(.privacy, step: 3))

            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("Protect your codes")
                card {
                    switchRow(appLockLabel, icon: "faceid", isOn: appLockBinding)
                    cardDivider
                    switchRow("Hide codes in app switcher", icon: "square.on.square", isOn: $hideCodesInAppSwitcher)
                    cardDivider
                    switchRow("Hide codes while recording or mirroring", icon: "record.circle", isOn: $hideCodesWhenScreenCaptured)
                    cardDivider
                    switchRow("Blur when backgrounded", icon: "drop", isOn: $enablePrivacyBlur)
                }

                Text("You can change any of these later in Settings › Privacy.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            .padding(.top, 8)
            .modifier(reveal(.privacy, step: 4))
        }
    }

    private var readyPage: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)

            OrbitHero(isShown: isRevealed(.ready), animated: !reduceMotion,
                      isOnScreen: currentPage == Page.ready.rawValue, satellites: [], size: 230) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color.accentColor.opacity(0.85), Color.accentColor],
                                             startPoint: .top, endPoint: .bottom))
                    Image(systemName: "checkmark")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(.white)
                        .symbolEffect(.bounce, value: isRevealed(.ready) && !reduceMotion)
                }
                .frame(width: 104, height: 104)
                .shadow(color: Color.accentColor.opacity(0.35), radius: 20, y: 10)
            }

            VStack(spacing: 10) {
                Text("You're All Set")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .modifier(reveal(.ready, step: 2))

                Text("Add your first account to start generating codes.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .modifier(reveal(.ready, step: 3))
            }
            .padding(.top, 8)

            card {
                recapRow("Service logos", icon: "photo", isOn: choices.fetchIssuerLogos)
                cardDivider
                recapRow("App Lock", icon: "faceid", isOn: enableAppLock)
                cardDivider
                recapRow("Privacy screen", icon: "eye.slash", isOn: hideCodesInAppSwitcher || hideCodesWhenScreenCaptured)
                cardDivider
                if hasPairedWatch {
                    cardDivider
                    recapRow("Apple Watch", icon: "applewatch", isOn: sendCodesToWatch)
                }
                cardDivider
                recapRow("iCloud Sync", icon: "icloud", isOn: isICloudSyncEnabled)
            }
            .padding(.top, 28)
            .modifier(reveal(.ready, step: 4))

            Spacer(minLength: 12)
        }
        .readableWidth(ReadableWidth.prose)
        .padding(.horizontal, 24)
    }

    // MARK: - Building blocks

    /// A scrolling page with a header, for the pages with more than fits.
    private func page<Content: View>(_ page: Page,
                                     icon: String,
                                     title: LocalizedStringKey,
                                     subtitle: LocalizedStringKey,
                                     @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(LinearGradient(colors: [Color.accentColor.opacity(0.85), Color.accentColor],
                                                 startPoint: .top, endPoint: .bottom))
                    )
                    .shadow(color: Color.accentColor.opacity(0.3), radius: 12, y: 6)
                    .accessibilityHidden(true)
                    .modifier(reveal(page, step: 0))

                Text(title)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 20)
                    .modifier(reveal(page, step: 1))

                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                    .modifier(reveal(page, step: 2))

                content()
            }
            .readableWidth(ReadableWidth.prose)
            .padding(.horizontal, 24)
            .padding(.top, 32)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
        )
    }

    private var cardDivider: some View {
        Divider().padding(.leading, 62)
    }

    private func sectionHeader(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 4)
    }

    private func rowIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .frame(width: 34, height: 34)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
            )
            .accessibilityHidden(true)
    }

    private func featureRow(icon: String, title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            rowIcon(icon)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .accessibilityElement(children: .combine)
    }

    /// A switch whose whole row is a button.
    ///
    /// A plain `Toggle` here only responded to a press held a moment: the page
    /// sits in a `ScrollView` inside the paging `TabView`, and between them they
    /// delay a touch long enough for a quick click to be lost. A button gets the
    /// click, so the row flips the value and the switch only draws it.
    private func switchRow(_ title: LocalizedStringKey,
                           icon: String,
                           detail: LocalizedStringKey? = nil,
                           isOn: Binding<Bool>) -> some View {
        Button {
            Haptics.impact(.light)
            withAnimation(reduceMotion ? nil : .snappy) {
                isOn.wrappedValue.toggle()
            }
        } label: {
            HStack(alignment: .top, spacing: 14) {
                rowIcon(icon)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 10) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Toggle(isOn: .constant(isOn.wrappedValue)) { EmptyView() }
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .tint(.accentColor)
                            .allowsHitTesting(false)
                    }
                    .frame(minHeight: 34)

                    if let detail {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(isOn.wrappedValue ? "On" : "Off"))
        .accessibilityHint(detail.map { Text($0) } ?? Text(verbatim: ""))
        .accessibilityAddTraits(.isToggle)
    }

    private func recapRow(_ title: LocalizedStringKey, icon: String, isOn: Bool) -> some View {
        HStack(spacing: 14) {
            rowIcon(icon)
            Text(title)
                .font(.body)
            Spacer()
            Text(isOn ? "On" : "Off")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isOn ? Color.accentColor : .secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    // MARK: - App Lock

    /// The App Lock switch's label: a Mac has no Face ID, and without Touch ID
    /// it falls back to the login password. Same strings as Settings.
    private var appLockLabel: LocalizedStringKey {
        #if os(macOS)
        return "Require Touch ID or password"
        #else
        return "Require Face ID / Touch ID"
        #endif
    }

    /// Turns on only when the device can authenticate its owner, as in
    /// Settings. Turning it off asks for nothing here: there are no codes yet to
    /// protect, and Settings asks once there are.
    private var appLockBinding: Binding<Bool> {
        Binding(
            get: { enableAppLock },
            set: { newValue in
                if newValue && !AppLockManager.canLock() {
                    showingAppLockUnavailable = true
                } else {
                    enableAppLock = newValue
                }
            }
        )
    }

    // MARK: - Bottom controls

    private var pageDots: some View {
        HStack(spacing: 7) {
            ForEach(Page.allCases, id: \.rawValue) { page in
                Capsule()
                    .fill(page.rawValue == currentPage ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(width: page.rawValue == currentPage ? 22 : 7, height: 7)
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8), value: currentPage)
        .accessibilityElement()
        .accessibilityLabel(Text("Page \(currentPage + 1) of \(Page.allCases.count)"))
    }

    private var navigationButtons: some View {
        HStack(spacing: 12) {
            if currentPage > 0 {
                Button {
                    Haptics.impact(.light)
                    currentPage -= 1
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .frame(width: 54, height: 54)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .onboardingGlass()
                .accessibilityLabel(Text("Back"))
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }

            Button {
                if isLastPage {
                    Haptics.notify(.success)
                    choices.complete()
                } else {
                    Haptics.impact(.medium)
                    currentPage += 1
                }
            } label: {
                Text(advanceTitle)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Capsule().fill(Color.accentColor))
                    .contentShape(Capsule())
            }
            .buttonStyle(PressableButtonStyle(reduceMotion: reduceMotion))
            .keyboardShortcut(.defaultAction)
        }
        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85), value: currentPage)
    }
}

// MARK: - Pieces

/// One page element's entrance: it fades in and rises into place.
private struct RevealModifier: ViewModifier {
    let isRevealed: Bool
    let delay: Double
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isRevealed ? 1 : 0)
            .offset(y: isRevealed || reduceMotion ? 0 : 14)
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.2)
                    : .spring(response: 0.6, dampingFraction: 0.9).delay(delay),
                value: isRevealed
            )
    }
}

/// Shrinks a little while held, which a plain button style doesn't do.
private struct PressableButtonStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

private extension View {
    /// Liquid Glass where the system has it, a material where it doesn't (the
    /// Mac app still runs on macOS 14).
    @ViewBuilder
    func onboardingGlass() -> some View {
        if #available(iOS 26, macOS 26, *) {
            self.glassEffect(.regular.interactive(), in: Circle())
        } else {
            self.background(.regularMaterial, in: Circle())
        }
    }
}

/// A calm grouped background with one soft glow from the top, so every page
/// sits on the same light.
private struct OnboardingBackground: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(.systemGroupedBackground)
                RadialGradient(
                    colors: [Color.accentColor.opacity(0.16), Color.accentColor.opacity(0)],
                    center: .init(x: 0.5, y: 0.1),
                    startRadius: 0,
                    endRadius: max(proxy.size.width, proxy.size.height) * 0.55
                )
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// A centrepiece inside two orbit rings, with small symbols travelling round
/// the outer one.
///
/// It assembles itself the first time its page shows: the rings draw in, the
/// centre springs up, and the satellites pop on one after another. After
/// that, the satellites drift slowly round and stay upright as they go.
private struct OrbitHero<Center: View>: View {
    let isShown: Bool
    let animated: Bool
    /// Whether its page is the one showing. The paging view keeps neighbouring
    /// pages alive, and the orbit stops turning — and redrawing — while it is
    /// off-screen, then carries on from where it stopped.
    let isOnScreen: Bool
    let satellites: [String]
    var size: CGFloat = 290
    @ViewBuilder let center: () -> Center

    /// Seconds per turn.
    private let period: TimeInterval = 120

    /// The angle reached before the orbit last stopped, and when it set off
    /// again, so a pause doesn't make it jump.
    @State private var settledAngle: Double = 0
    @State private var movingSince: Date?

    private var turns: Bool { animated && isOnScreen && !satellites.isEmpty }

    private func spin(at date: Date) -> Double {
        guard let movingSince else { return settledAngle }
        return settledAngle + date.timeIntervalSince(movingSince) / period * 360
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color.accentColor.opacity(0.22), Color.accentColor.opacity(0)],
                                     center: .center, startRadius: 0, endRadius: size * 0.5))
                .scaleEffect(isShown ? 1 : 0.6)
                .opacity(isShown ? 1 : 0)
                .animation(.easeOut(duration: 1.0), value: isShown)

            ring(diameter: size * 0.62, dashed: false, delay: 0.05)
            ring(diameter: size * 0.94, dashed: true, delay: 0.15)

            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !turns)) { context in
                let spinAngle = spin(at: context.date)
                ZStack {
                    ForEach(Array(satellites.enumerated()), id: \.offset) { index, symbol in
                        satellite(symbol, index: index, spinAngle: spinAngle)
                    }
                }
            }

            center()
                .scaleEffect(isShown || !animated ? 1 : 0.7)
                .opacity(isShown ? 1 : 0)
                .animation(animated ? .spring(response: 0.6, dampingFraction: 0.65).delay(0.1) : .easeOut(duration: 0.2),
                           value: isShown)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .onAppear { if turns { movingSince = Date() } }
        .onChange(of: turns) { _, turning in
            let now = Date()
            if turning {
                movingSince = now
            } else {
                settledAngle = spin(at: now)
                movingSince = nil
            }
        }
    }

    private func satellite(_ symbol: String, index: Int, spinAngle: Double) -> some View {
        let angle = Double(index) / Double(satellites.count) * 360 - 90 + spinAngle
        return Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .frame(width: 40, height: 40)
            .background(Circle().fill(Color(.secondarySystemGroupedBackground)))
            .overlay(Circle().strokeBorder(Color.accentColor.opacity(0.15)))
            .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
            .scaleEffect(isShown ? 1 : 0.2)
            .opacity(isShown ? 1 : 0)
            .animation(
                animated
                    ? .spring(response: 0.5, dampingFraction: 0.6).delay(0.5 + 0.12 * Double(index))
                    : .easeOut(duration: 0.2),
                value: isShown
            )
            // Counter-rotated, so the symbol stays upright on its way round.
            .rotationEffect(.degrees(-angle))
            .offset(x: size * 0.47)
            .rotationEffect(.degrees(angle))
    }

    private func ring(diameter: CGFloat, dashed: Bool, delay: Double) -> some View {
        Circle()
            .trim(from: 0, to: isShown ? 1 : 0)
            .stroke(Color.accentColor.opacity(dashed ? 0.22 : 0.16),
                    style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: dashed ? [2, 6] : []))
            .rotationEffect(.degrees(-90))
            .frame(width: diameter, height: diameter)
            .animation(animated ? .easeInOut(duration: 1.1).delay(delay) : .easeOut(duration: 0.2), value: isShown)
    }
}

#Preview("Light") {
    WelcomeView()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    WelcomeView()
        .preferredColorScheme(.dark)
}

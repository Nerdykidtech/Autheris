import Combine
import SwiftUI
#if os(iOS)
import UIKit
#endif

@main
struct AutherisApp: App {
    // The delegate is the same object on both platforms — it only registers for
    // remote notifications and routes CloudKit silent pushes — so only the
    // adaptor that installs it differs.
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #else
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("enablePrivacyBlur") private var enablePrivacyBlur = true
    @AppStorage("hideCodesInAppSwitcher") private var hideCodesInAppSwitcher = true
    @AppStorage("hideCodesWhenScreenCaptured") private var hideCodesWhenScreenCaptured = true
    @AppStorage("accentTheme") private var accentThemeRaw = ""
    @StateObject private var dataStore = OTPDataStore()
    @StateObject private var appLock = AppLockManager()
    /// Keeps the app's windows out of screen capture on the Mac. A no-op on iOS,
    /// where capture can be detected instead.
    @StateObject private var captureExclusion = WindowCaptureExclusion()
    @State private var showingImportSheet = false
    /// Codes from an incoming link, waiting for the user to accept or reject them.
    @State private var pendingImport: [OTPCode]?
    @State private var otpSetupResult: (title: String, body: String)?
    @State private var isAppActive = true
    @State private var isScreenCaptured = false
    @State private var showPrivacyOverlay = false

    private var selectedAccent: AccentTheme? {
        AccentTheme(rawValue: accentThemeRaw)
    }

    /// What the device is doing right now, and what the user asked for. Both are
    /// handed to `PrivacyShield`, which owns the actual rules so that they can be
    /// unit tested without a simulator.
    private var privacyConditions: PrivacyShield.Conditions {
        PrivacyShield.Conditions(appIsActive: isAppActive, screenIsCaptured: isScreenCaptured)
    }

    private var privacyPreferences: PrivacyShield.Preferences {
        PrivacyShield.Preferences(blurWhenBackgrounded: enablePrivacyBlur,
                                  hideInAppSwitcher: hideCodesInAppSwitcher,
                                  hideWhenScreenCaptured: hideCodesWhenScreenCaptured)
    }

    private var shouldBlurContent: Bool {
        PrivacyShield.shouldBlur(privacyConditions, privacyPreferences)
    }
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                if hasCompletedOnboarding {
                    if appLock.isLocked {
                        AppLockView(manager: appLock)
                            .transition(.opacity)
                    } else {
                        ContentView()
                            .environmentObject(dataStore)
                            .blur(radius: shouldBlurContent ? 10 : 0)
                            .opacity(shouldBlurContent ? 0.7 : 1)
                    }
                } else {
                    WelcomeView()
                        .blur(radius: shouldBlurContent ? 10 : 0)
                        .opacity(shouldBlurContent ? 0.7 : 1)
                }
                
                // Import sheet overlay - shows on top of everything, but only to
                // someone who is past onboarding and App Lock. A link that
                // arrives while the app is locked waits here until it is
                // unlocked, rather than being offered on top of the lock screen.
                if showingImportSheet && hasCompletedOnboarding && !appLock.isLocked {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .ignoresSafeArea()
                        .overlay(Color.black.opacity(0.25))
                        .transition(.opacity)
                    
                    if let tokens = pendingImport {
                        ImportConfirmationView(tokens: tokens, dataStore: dataStore, isPresented: $showingImportSheet)
                            .transition(.scale.combined(with: .opacity))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                
                // Privacy screen: covers the app switcher and the home screen,
                // and a screen that is being recorded or mirrored.
                // `showPrivacyOverlay` already folds in the relevant settings.
                if showPrivacyOverlay {
                    PrivacyOverlay()
                        .transition(.opacity)
                        .zIndex(1) // Ensure it's on top
                }
            }
            .onOpenURL { url in
                #if DEBUG
                // Only scheme and host: an `autheris://import` URL carries the
                // exported tokens (including their secrets) in its `data` item.
                print("App received URL: \(url.scheme ?? "?")://\(url.host ?? "")")
                #endif
                handleIncomingURL(url)
            }
            .alert(
                Text(otpSetupResult?.title ?? "Autheris"),
                isPresented: Binding(
                    get: { otpSetupResult != nil },
                    set: { if !$0 { otpSetupResult = nil } }
                ),
                presenting: otpSetupResult
            ) { _ in
                Button("OK") { otpSetupResult = nil }
            } message: { result in
                Text(result.body)
            }
            .animation(.easeInOut(duration: 0.3), value: showingImportSheet)
            .animation(.easeInOut(duration: 0.3), value: hasCompletedOnboarding)
            .animation(.easeInOut(duration: 0.3), value: isAppActive)
            .animation(.easeInOut(duration: 0.3), value: showPrivacyOverlay)
            .tint(selectedAccent?.color ?? .accentColor)
            .windowCaptureExclusion(captureExclusion)
            .onAppear {
                #if DEBUG
                print("App appeared, hasCompletedOnboarding: \(hasCompletedOnboarding)")
                #endif

                // Reinstall wipes UserDefaults but not the Keychain, so a user can
                // end up with existing tokens and a reset onboarding flag. In that
                // case skip onboarding and keep their tokens visible.
                if !hasCompletedOnboarding && !dataStore.codes.isEmpty {
                    hasCompletedOnboarding = true
                }

                // Keep the Keychain copy of the preferences current. Only the
                // first window to appear installs the observer.
                PreferencesStore.startMirroringChanges()

                // Take an initial reading of the capture state in case the app
                // launched into an active recording.
                refreshScreenCaptureState()

                // Apply the saved capture preference to the windows themselves.
                captureExclusion.setExcluding(hideCodesWhenScreenCaptured)
            }
            // App state changes. `AppActivity` names the platform's own
            // notification for each of these four moments, so the privacy rules
            // read the same on both platforms. `onReceive` subscribes for as long
            // as this window exists, so a closed window stops listening; every
            // open window sets the same app-wide state, which is harmless.
            .onReceive(NotificationCenter.default.publisher(for: AppActivity.willResignActive)) { _ in
                #if DEBUG
                print("App will resign active")
                #endif
                isAppActive = false
                updatePrivacyOverlay()
            }
            .onReceive(NotificationCenter.default.publisher(for: AppActivity.didBecomeActive)) { _ in
                #if DEBUG
                print("App did become active")
                #endif
                isAppActive = true
                refreshScreenCaptureState()
            }
            .onReceive(NotificationCenter.default.publisher(for: AppActivity.didLeaveForeground)) { _ in
                #if DEBUG
                print("App left the foreground")
                #endif
                isAppActive = false
                updatePrivacyOverlay()
            }
            .onReceive(NotificationCenter.default.publisher(for: AppActivity.willEnterForeground)) { _ in
                #if DEBUG
                print("App will enter foreground")
                #endif
                isAppActive = true
                refreshScreenCaptureState()
            }
            // Recording or mirroring can begin while the app stays frontmost, which
            // never resigns active and is therefore invisible to every notification
            // above. This is the only signal iOS gives for it, and macOS gives none:
            // there it is a publisher that never fires.
            .onReceive(screenCaptureChanges) { _ in
                refreshScreenCaptureState()
            }
            .onChange(of: isAppActive) { oldValue, newValue in
                #if DEBUG
                print("App active state changed: \(newValue)")
                #endif
                // Update privacy overlay based on app state and settings
                updatePrivacyOverlay()
            }
            .onChange(of: hideCodesInAppSwitcher) { oldValue, newValue in
                // Update privacy overlay when setting changes
                updatePrivacyOverlay()
            }
            .onChange(of: hideCodesWhenScreenCaptured) { oldValue, newValue in
                // Update privacy overlay when setting changes, and on the Mac
                // apply the setting to the windows themselves — there is no
                // capture to notice, so the exclusion *is* the protection.
                captureExclusion.setExcluding(newValue)
                updatePrivacyOverlay()
            }
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .background:
                    appLock.appDidEnterBackground()
                case .active:
                    appLock.appDidBecomeActive()
                default:
                    break
                }

                // Foregrounding is the cheapest reliable moment to pick up anything
                // a silent push may have missed, and to re-check the iCloud account.
                guard newPhase == .active, hasCompletedOnboarding else { return }
                // Foregrounding is also the cheapest reliable moment to retire any
                // trashed codes that have passed their retention window.
                dataStore.purgeExpiredTrash()
                Task {
                    await dataStore.refreshSyncAvailability()
                    await dataStore.syncNow()
                }
            }
        }

        #if os(macOS)
        // A real preferences window rather than a sheet: it gives Autheris the
        // standard "Settings…" menu item and ⌘, for free, and it is what a Mac user
        // reaches for. The iPad keeps the sheet.
        //
        // It is its own window, outside the `WindowGroup` above, so it needs its
        // own App Lock gate: otherwise ⌘, on a locked Mac opens QR transfer,
        // unencrypted backups and the App Lock toggle itself.
        Settings {
            Group {
                if appLock.isLocked {
                    AppLockView(manager: appLock)
                        // The preferences window's size, so it doesn't jump on unlock.
                        .frame(width: 620, height: 520)
                } else {
                    SettingsView(dataStore: dataStore, presentation: .preferences)
                }
            }
            .windowCaptureExclusion(captureExclusion)
        }
        #endif
    }
    
    /// Every link Autheris is opened with lands here. Nothing is added to the
    /// vault from this function: codes go to `ImportConfirmationView`, which
    /// shows them only once the app is unlocked and adds them only on Import.
    private func handleIncomingURL(_ url: URL) {
        #if DEBUG
        // Redacted for the same reason as above: the payload is in the query.
        print("Handling incoming URL: \(url.scheme ?? "?")://\(url.host ?? "")")
        #endif

        switch IncomingLink.parse(url) {
        case .tokens(let tokens):
            pendingImport = tokens
            showingImportSheet = true
        case .failure(let title, let message):
            otpSetupResult = (title, message)
        case nil:
            #if DEBUG
            print("Not a URL Autheris handles")
            #endif
        }
    }

    /// Posts whenever the screen starts or stops being recorded or mirrored, on
    /// iOS. macOS has no such notification, so there it never posts.
    private var screenCaptureChanges: AnyPublisher<Notification, Never> {
        guard let name = AppActivity.screenCaptureChanged else {
            return Empty(completeImmediately: false).eraseToAnyPublisher()
        }
        return NotificationCenter.default.publisher(for: name).eraseToAnyPublisher()
    }

    private func updatePrivacyOverlay() {
        showPrivacyOverlay = PrivacyShield.shouldShowOverlay(privacyConditions, privacyPreferences)
        #if DEBUG
        print("Privacy overlay: \(showPrivacyOverlay), appIsActive: \(isAppActive), screenIsCaptured: \(isScreenCaptured), hideCodesInAppSwitcher: \(hideCodesInAppSwitcher), hideCodesWhenScreenCaptured: \(hideCodesWhenScreenCaptured)")
        #endif
    }

    /// Re-reads whether the screen is being recorded or mirrored.
    ///
    /// Called on became-active as well as on the capture notification: a
    /// recording that began while the app was in the background may have posted
    /// its change before the observer existed, and there is no way to ask "was it
    /// already recording when you started?" after the fact.
    private func refreshScreenCaptureState() {
        isScreenCaptured = ScreenCaptureMonitor.isCaptured
        updatePrivacyOverlay()
    }
}

// MARK: - Privacy Overlay View
struct PrivacyOverlay: View {
    var body: some View {
        ZStack {
            // Blurred background
            Rectangle()
                .fill(.ultraThickMaterial)
                .ignoresSafeArea()
            
            // Privacy message (centered)
            VStack(spacing: 16) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.accentColor)
                    .symbolRenderingMode(.hierarchical)
                
                Text("Autheris")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Text("Protected by Privacy Mode")
                    .font(.system(size: 16, weight: .medium, design: .default))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }
}


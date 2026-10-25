import SwiftUI
import LocalAuthentication
import Combine
#if os(macOS)
import AppKit
#endif

/// Shared UserDefaults key so the Settings toggle and the lock manager cannot drift.
nonisolated let AppLockEnabledKey = "enableAppLock"

/// The part of `LAContext` App Lock uses, so tests can stand in a device that has
/// no passcode, or one that refuses.
nonisolated protocol DeviceOwnerAuthenticating {
    /// Which biometry the device has. Only meaningful once `canEvaluatePolicy`
    /// has been called on the same context; `.none` before that.
    var biometryType: LABiometryType { get }
    func canEvaluatePolicy(_ policy: LAPolicy, error: NSErrorPointer) -> Bool
    func evaluatePolicy(_ policy: LAPolicy,
                        localizedReason: String,
                        reply: @escaping @Sendable (Bool, (any Error)?) -> Void)
}

extension LAContext: DeviceOwnerAuthenticating {}

extension DeviceOwnerAuthenticating {
    /// Whether the device can authenticate its owner and, when it can't, why.
    func ownerAuthenticationAvailability() -> (available: Bool, error: NSError?) {
        var error: NSError?
        let available = canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
        return (available, error)
    }
}

final class AppLockManager: ObservableObject {
    @Published private(set) var isLocked: Bool
    @Published var errorMessage: String?
    /// The biometry the unlock button can name: Face ID or Touch ID when the app
    /// may actually use it, `.none` otherwise. See `currentUnlockBiometry()`.
    @Published private(set) var unlockBiometry: LABiometryType = .none

    /// How long the app can stay in the background before the lock re-engages.
    /// Kept short enough to be useful, long enough to avoid re-prompting when the
    /// user quickly switches apps to copy a code.
    private let gracePeriod: TimeInterval = 30
    private var backgroundedAt: Date?
    /// A fresh context per attempt, as `LAContext` expects. Injectable for tests.
    private let makeContext: () -> DeviceOwnerAuthenticating
    /// The time, injectable so tests can step past the grace period.
    private let now: () -> Date
    /// The context of the attempt in progress, handed to the vault on success.
    private var pendingUnlockContext: LAContext?

    #if os(macOS)
    /// Activation observers, each with the centre it was added to, held so they
    /// are removed with the manager.
    ///
    /// `nonisolated(unsafe)` only so `deinit`, which is not main-actor isolated,
    /// can read it. It is written once in `init` and read once in `deinit`, when
    /// nothing else can still be holding the manager.
    nonisolated(unsafe) private var activationObservers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    #endif

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: AppLockEnabledKey)
    }

    init(makeContext: @escaping () -> DeviceOwnerAuthenticating = { LAContext() },
         now: @escaping () -> Date = Date.init) {
        self.makeContext = makeContext
        self.now = now
        // Restore Keychain-backed preferences before reading the lock setting.
        PreferencesStore.restoreIntoUserDefaults()

        // Cold launches always start locked when the feature is enabled.
        isLocked = UserDefaults.standard.bool(forKey: AppLockEnabledKey)
        unlockBiometry = currentUnlockBiometry()

        #if os(macOS)
        // On iOS the scene phase drives the lock. A Mac window that loses focus
        // to another app only reaches `.inactive`, though — `.background` takes
        // minimising or hiding — so on the Mac, leaving the app is what starts
        // the grace period. Observed here rather than in a view so that it works
        // whichever windows are open, including none.
        //
        // Leaving also covers the moments the app stays frontmost but nobody is
        // in front of it: the screen locking or sleeping, another user taking
        // over the session, and the last window closing with the app still
        // active. None of those resigns active, so each starts the grace period
        // itself, and coming back from it is checked the way returning to the app
        // is.
        let center = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        func observe(_ observed: NotificationCenter, _ name: Notification.Name,
                     _ action: @escaping @MainActor (AppLockManager, Notification) -> Void) {
            let token = observed.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                MainActor.assumeIsolated {
                    if let self { action(self, notification) }
                }
            }
            activationObservers.append((observed, token))
        }

        observe(center, AppActivity.willResignActive) { manager, _ in manager.appDidEnterBackground() }
        observe(center, AppActivity.didBecomeActive) { manager, _ in manager.appDidBecomeActive() }

        for name in [Notification.Name("com.apple.screenIsLocked")] {
            observe(distributed, name) { manager, _ in manager.appDidEnterBackground() }
        }
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observe(workspace, name) { manager, _ in manager.appDidEnterBackground() }
        }
        // Back from any of those, but only counted as a return to Autheris when
        // it is the frontmost app; otherwise the user is still away from it.
        for name in [Notification.Name("com.apple.screenIsUnlocked")] {
            observe(distributed, name) { manager, _ in manager.returnIfFrontmost() }
        }
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observe(workspace, name) { manager, _ in manager.returnIfFrontmost() }
        }

        // The last window closing, with the app still frontmost. Reopening it from
        // the Dock makes a window key without the app ever becoming active again,
        // so a window becoming key is the return.
        observe(center, NSWindow.willCloseNotification) { manager, notification in
            guard let closing = notification.object as? NSWindow else { return }
            let othersRemain = NSApplication.shared.windows.contains {
                $0 !== closing && $0.isVisible && $0.canBecomeMain
            }
            if !othersRemain { manager.appDidEnterBackground() }
        }
        observe(center, NSWindow.didBecomeKeyNotification) { manager, _ in
            manager.returnIfFrontmost()
        }
        #endif
    }

    #if os(macOS)
    deinit {
        for observer in activationObservers {
            observer.center.removeObserver(observer.token)
        }
    }

    /// A return from a screen lock, sleep, session switch or closed window, which
    /// is only a return to the app if the app is in front.
    private func returnIfFrontmost() {
        guard backgroundedAt != nil, NSApplication.shared.isActive else { return }
        appDidBecomeActive()
    }
    #endif

    /// Starts the grace period, unless it has already started.
    ///
    /// The earliest moment counts. Leaving the app and then locking the Mac five
    /// minutes later is five minutes away, not the few seconds since the lock —
    /// restarting the clock at the second event would let an unlock moments later
    /// skip the re-lock that was already due.
    func appDidEnterBackground() {
        guard isEnabled, backgroundedAt == nil else { return }
        backgroundedAt = now()
    }

    func appDidBecomeActive() {
        // Face ID can be turned off for the app in Settings while it is away.
        unlockBiometry = currentUnlockBiometry()
        guard isEnabled else {
            isLocked = false
            return
        }

        if shouldLockOnForeground {
            isLocked = true
            // Locking gives up the authentication the vault was read with.
            VaultSession.shared.end()
        }

        // Consume the transition so the Face ID / Touch ID prompt's own
        // .inactive -> .active cycle can't re-lock right after a successful scan.
        backgroundedAt = nil
    }

    private var shouldLockOnForeground: Bool {
        // Only re-lock after a real backgrounding. The Face ID / Touch ID prompt
        // can briefly push the scene through .inactive -> .active, and treating
        // that as a foreground event would re-lock right after a successful scan.
        guard let backgroundedAt else { return false }
        return now().timeIntervalSince(backgroundedAt) > gracePeriod
    }

    /// Asked of a fresh context, through the biometrics-only policy.
    ///
    /// `biometryType` describes the hardware, so it says Face ID even when the
    /// user has refused Face ID to this app — and then the button would promise
    /// Face ID and the system would ask for the passcode. Asking whether the
    /// biometrics policy can be evaluated first is what tells those apart, and is
    /// also what fills in `biometryType` at all: read from a context nobody has
    /// asked, it is always `.none`, which is why the lock screen never named
    /// either.
    private func currentUnlockBiometry() -> LABiometryType {
        let context = makeContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else {
            return .none
        }
        return context.biometryType
    }

    /// `context` is the authentication that just succeeded, which the vault now
    /// uses. Without one (an unlock that didn't come from `authenticate`), the vault
    /// stays unreadable until the owner authenticates.
    func unlock(with context: LAContext? = nil) {
        isLocked = false
        errorMessage = nil
        backgroundedAt = nil
        if let context {
            VaultSession.shared.begin(context)
        }
    }

    /// Asks the owner to authenticate before the vault is moved into or out of App
    /// Lock's protected form. Returns the context that authenticated, for
    /// `VaultKeychain.moveAll`, or `nil` when they didn't or can't.
    static func authenticateForVault(reason: String) async -> LAContext? {
        let context = LAContext()
        guard context.ownerAuthenticationAvailability().available else { return nil }
        let succeeded = await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
                continuation.resume(returning: success)
            }
        }
        return succeeded ? context : nil
    }

    /// Asks for Face ID, Touch ID or the passcode again before a sensitive action:
    /// turning App Lock off, exporting or backing up every secret, or showing a
    /// setup key. This applies whether or not App Lock is on, because these actions
    /// reveal every code and App Lock is not the only thing that should guard them.
    ///
    /// The grace period means a phone unlocked moments ago opens straight into
    /// Autheris, so without this anyone holding it could export the whole vault.
    /// Returns `true` straight away only when the device has no passcode, since there
    /// is then nothing to authenticate with.
    static func reauthenticate(reason: String,
                               context: DeviceOwnerAuthenticating = LAContext()) async -> Bool {
        let availability = context.ownerAuthenticationAvailability()
        guard availability.available else {
            return (availability.error as? LAError)?.code == .passcodeNotSet
        }

        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }

    /// Whether this device can authenticate its owner at all, which App Lock
    /// needs before it can be turned on. `false` when it has no passcode.
    static func canLock(context: DeviceOwnerAuthenticating = LAContext()) -> Bool {
        context.ownerAuthenticationAvailability().available
    }

    /// Evaluate device owner authentication (Face ID, Touch ID, or passcode fallback).
    func authenticate() {
        let context = makeContext()
        let reason = String(localized: "Unlock Autheris to view your tokens.")

        let availability = context.ownerAuthenticationAvailability()
        guard availability.available else {
            // With no passcode there is nothing to authenticate with — the answer
            // `reauthenticate` already gives. Holding the lock here would leave the
            // user on this screen for good, on every launch, with no way past it.
            // App Lock is turned off as well, so Settings doesn't go on showing a
            // lock that no longer locks anything.
            if (availability.error as? LAError)?.code == .passcodeNotSet {
                // Codes bound to the passcode can't be read without one. Turning App
                // Lock off here would read the vault as empty and then save that over
                // it, so the lock stays until a passcode is set.
                guard !VaultKeychain.hasBoundItems() else {
                    errorMessage = String(localized: "Set a device passcode to unlock your codes. They were protected by it and can't be read without one.")
                    return
                }
                UserDefaults.standard.set(false, forKey: AppLockEnabledKey)
                unlock()
                return
            }
            errorMessage = availability.error?.localizedDescription
                ?? String(localized: "Biometric authentication is unavailable.")
            return
        }

        // Held here rather than captured by the reply, which is @Sendable and can't
        // carry the context across. The unlock below reads it back.
        pendingUnlockContext = context as? LAContext
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { [weak self] success, authError in
            // Bind the weak capture to a plain local *before* the task: the task
            // body runs concurrently, and reading the closure's own mutable weak
            // storage from there is what Swift 6 rejects. `AppLockManager` is
            // main-actor isolated, so the binding is Sendable.
            let manager = self
            Task { @MainActor in
                guard let manager else { return }
                if success {
                    manager.unlock(with: manager.pendingUnlockContext)
                    manager.pendingUnlockContext = nil
                } else if let laError = authError as? LAError {
                    switch laError.code {
                    case .userCancel, .systemCancel, .appCancel:
                        // The user dismissed the prompt; leave the lock in place quietly.
                        break
                    default:
                        manager.errorMessage = laError.localizedDescription
                    }
                } else {
                    manager.errorMessage = authError?.localizedDescription
                        ?? String(localized: "Authentication failed.")
                }
            }
        }
    }
}

// MARK: - Lock Screen

struct AppLockView: View {
    @ObservedObject var manager: AppLockManager
    @State private var didAutoPrompt = false

    private var biometryIcon: String {
        switch manager.unlockBiometry {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        default: return "lock"
        }
    }

    /// `LocalizedStringKey`, not `String`: a `String` would reach `Label` as
    /// already-resolved text and never be looked up in the catalog.
    private var unlockTitle: LocalizedStringKey {
        switch manager.unlockBiometry {
        case .faceID: return "Unlock with Face ID"
        case .touchID: return "Unlock with Touch ID"
        default: return "Unlock"
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(.systemBackground),
                    Color.accentColor.opacity(0.08)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.accentColor)
                    .symbolRenderingMode(.hierarchical)

                Text("Autheris")
                    .font(.system(size: 34, weight: .bold, design: .rounded))

                Text("Unlock to view your tokens")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let errorMessage = manager.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer()

                Button {
                    manager.authenticate()
                } label: {
                    Label(unlockTitle, systemImage: biometryIcon)
                        .font(.headline)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(Color.accentColor))
                        .foregroundStyle(.white)
                }
                .padding(.bottom, 48)
            }
            .padding(.horizontal, 32)
        }
        .onAppear {
            guard !didAutoPrompt else { return }
            didAutoPrompt = true

            // Give the app a beat to finish appearing before presenting biometrics.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                manager.authenticate()
            }
        }
    }
}

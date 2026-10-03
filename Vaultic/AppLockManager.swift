import SwiftUI
import LocalAuthentication
import Combine

/// Shared UserDefaults key so the Settings toggle and the lock manager cannot drift.
let AppLockEnabledKey = "enableAppLock"

/// The part of `LAContext` App Lock uses, so tests can stand in a device that has
/// no passcode, or one that refuses.
nonisolated protocol DeviceOwnerAuthenticating {
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

    /// How long the app can stay in the background before the lock re-engages.
    /// Kept short enough to be useful, long enough to avoid re-prompting when the
    /// user quickly switches apps to copy a code.
    private let gracePeriod: TimeInterval = 30
    private var backgroundedAt: Date?
    /// A fresh context per attempt, as `LAContext` expects. Injectable for tests.
    private let makeContext: () -> DeviceOwnerAuthenticating

    #if os(macOS)
    /// Activation observers, held so they are removed with the manager.
    ///
    /// `nonisolated(unsafe)` only so `deinit`, which is not main-actor isolated,
    /// can read it. It is written once in `init` and read once in `deinit`, when
    /// nothing else can still be holding the manager.
    nonisolated(unsafe) private var activationObservers: [NSObjectProtocol] = []
    #endif

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: AppLockEnabledKey)
    }

    init(makeContext: @escaping () -> DeviceOwnerAuthenticating = { LAContext() }) {
        self.makeContext = makeContext
        // Restore Keychain-backed preferences before reading the lock setting.
        PreferencesStore.restoreIntoUserDefaults()

        // Cold launches always start locked when the feature is enabled.
        isLocked = UserDefaults.standard.bool(forKey: AppLockEnabledKey)

        #if os(macOS)
        // On iOS the scene phase drives the lock. A Mac window that loses focus
        // to another app only reaches `.inactive`, though — `.background` takes
        // minimising or hiding — so on the Mac, leaving the app is what starts
        // the grace period. Observed here rather than in a view so that it works
        // whichever windows are open, including none.
        let center = NotificationCenter.default
        activationObservers = [
            center.addObserver(forName: AppActivity.willResignActive, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.appDidEnterBackground() }
            },
            center.addObserver(forName: AppActivity.didBecomeActive, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.appDidBecomeActive() }
            }
        ]
        #endif
    }

    #if os(macOS)
    deinit {
        activationObservers.forEach(NotificationCenter.default.removeObserver)
    }
    #endif

    func appDidEnterBackground() {
        guard isEnabled else { return }
        backgroundedAt = Date()
    }

    func appDidBecomeActive() {
        guard isEnabled else {
            isLocked = false
            return
        }

        if shouldLockOnForeground {
            isLocked = true
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
        return Date().timeIntervalSince(backgroundedAt) > gracePeriod
    }

    func unlock() {
        isLocked = false
        errorMessage = nil
        backgroundedAt = nil
    }

    /// Asks for Face ID, Touch ID or the passcode again before a sensitive action:
    /// turning App Lock off, exporting or backing up every secret, or showing a
    /// setup key.
    ///
    /// The grace period means a phone unlocked moments ago opens straight into
    /// Autheris, so without this anyone holding it could export the whole vault.
    /// Returns `true` straight away when App Lock is off, since the user has chosen
    /// not to be asked, and when the device has no passcode, since there is then
    /// nothing to authenticate with.
    static func reauthenticate(reason: String,
                               context: DeviceOwnerAuthenticating = LAContext()) async -> Bool {
        guard UserDefaults.standard.bool(forKey: AppLockEnabledKey) else { return true }

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
                UserDefaults.standard.set(false, forKey: AppLockEnabledKey)
                unlock()
                return
            }
            errorMessage = availability.error?.localizedDescription
                ?? String(localized: "Biometric authentication is unavailable.")
            return
        }

        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { [weak self] success, authError in
            // Bind the weak capture to a plain local *before* the task: the task
            // body runs concurrently, and reading the closure's own mutable weak
            // storage from there is what Swift 6 rejects. `AppLockManager` is
            // main-actor isolated, so the binding is Sendable.
            let manager = self
            Task { @MainActor in
                guard let manager else { return }
                if success {
                    manager.unlock()
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
        let context = LAContext()
        switch context.biometryType {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        default: return "lock"
        }
    }

    /// `LocalizedStringKey`, not `String`: a `String` would reach `Label` as
    /// already-resolved text and never be looked up in the catalog.
    private var unlockTitle: LocalizedStringKey {
        let context = LAContext()
        switch context.biometryType {
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

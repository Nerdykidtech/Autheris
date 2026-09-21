import SwiftUI
import LocalAuthentication
import Combine

/// Shared UserDefaults key so the Settings toggle and the lock manager cannot drift.
let AppLockEnabledKey = "enableAppLock"

final class AppLockManager: ObservableObject {
    @Published private(set) var isLocked: Bool
    @Published var errorMessage: String?

    /// How long the app can stay in the background before the lock re-engages.
    /// Kept short enough to be useful, long enough to avoid re-prompting when the
    /// user quickly switches apps to copy a code.
    private let gracePeriod: TimeInterval = 30
    private var backgroundedAt: Date?

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: AppLockEnabledKey)
    }

    init() {
        // Restore Keychain-backed preferences before reading the lock setting.
        PreferencesStore.restoreIntoUserDefaults()

        // Cold launches always start locked when the feature is enabled.
        isLocked = UserDefaults.standard.bool(forKey: AppLockEnabledKey)
    }

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

    /// Evaluate device owner authentication (Face ID, Touch ID, or passcode fallback).
    func authenticate() {
        let context = LAContext()
        var error: NSError?
        let reason = "Unlock Autheris to view your tokens."

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            errorMessage = error?.localizedDescription ?? "Biometric authentication is unavailable."
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
                    manager.errorMessage = authError?.localizedDescription ?? "Authentication failed."
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

    private var unlockTitle: String {
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

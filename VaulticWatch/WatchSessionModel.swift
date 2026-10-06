import Combine
import Foundation
import WatchConnectivity

/// The watch's copy of the token list.
///
/// The watch app is a viewer and nothing else: it has no add, no edit, no delete,
/// no settings and no way to copy a code. Every one of those lives on the iPhone,
/// and this type is the entire reason they can be absent here — it receives the
/// list the iPhone sends, keeps the newest copy, and nothing more.
///
/// ### Why it also caches to the Keychain
/// The system re-delivers the last application context on activation, so the
/// obvious design is to show `receivedApplicationContext` and be done. That is not
/// good enough for a credential app: the redelivery is a behaviour of the
/// framework rather than a documented guarantee, and the failure mode if it ever
/// stops is that a user reaches for their watch and sees **no codes** with no
/// explanation. The last received list is therefore written to the watch's own
/// Keychain, with the same `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
/// protection the phone uses, so the app opens to the real codes from the first
/// frame whether or not the phone is anywhere near.
@MainActor
final class WatchSessionModel: NSObject, ObservableObject {

    /// The codes to show, in the order the iPhone sent them.
    ///
    /// The watch deliberately does not reorder anything. Pinned-first ordering and
    /// the user's manual arrangement are the phone's (`TokenOrdering`), and they
    /// arrive already applied — so the watch cannot disagree with the phone about
    /// what order the codes are in.
    @Published private(set) var tokens: [OTPCode] = []

    /// Whether the iPhone has ever sent a payload.
    ///
    /// Kept separate from `tokens.isEmpty` because the two empty states need
    /// different words. "Your iPhone has no codes" and "your iPhone has not said
    /// anything yet" look identical on screen otherwise, and on a watch that is
    /// the difference between "add one on your phone" and "wait a moment".
    @Published private(set) var hasReceivedPayload = false

    /// The iPhone has "Send codes to Apple Watch" turned off, so the list is
    /// empty on purpose and the empty screen says how to turn it back on.
    @Published private(set) var sendingStopped = false

    private let session: WCSession?

    /// When the newest applied payload was sent.
    ///
    /// Persisted alongside the tokens, so a payload that arrives out of order
    /// after a relaunch still cannot roll the list back to an older one. See
    /// `WatchTokenPayload.isNewer`.
    private var appliedAt: Date = .distantPast

    /// Keychain account for the cached list. One item holding both the tokens and
    /// the stamp, so the two can never disagree about which payload they are.
    private static let cacheAccount = "watchTokenCache"

    override init() {
        // Before the session is touched: the first frame should be the real list,
        // not an empty state that is corrected a moment later.
        let cache = Self.loadCache()
        tokens = cache?.tokens ?? []
        appliedAt = cache?.appliedAt ?? .distantPast
        hasReceivedPayload = cache != nil
        sendingStopped = cache?.sendingStopped ?? false

        session = WCSession.isSupported() ? WCSession.default : nil

        super.init()

        session?.delegate = self
        session?.activate()

        // Activation is asynchronous — `activationDidComplete` will arrive shortly —
        // but a context the system already holds can be applied right now, which
        // closes the window where the app is on screen with nothing to show.
        if let session {
            apply(session.receivedApplicationContext)
        }
    }

    // MARK: - Receiving

    private func apply(_ applicationContext: [String: Any]) {
        guard let decoded = WatchTokenPayload.decode(applicationContext: applicationContext) else { return }
        apply(decoded)
    }

    private func apply(_ blob: Data) {
        guard let decoded = WatchTokenPayload.decode(blob) else { return }
        apply(decoded)
    }

    private func apply(_ decoded: WatchTokenPayload.Decoded) {
        // An older payload is not an error — it is the file transport and the
        // context transport settling in a different order than they were sent.
        guard WatchTokenPayload.isNewer(decoded, than: appliedAt) else { return }
        appliedAt = decoded.sentAt
        tokens = decoded.tokens
        sendingStopped = decoded.sendingStopped
        hasReceivedPayload = true
        saveCache()
    }

    // MARK: - Cache

    private struct Cache: Codable {
        let appliedAt: Date
        let tokens: [OTPCode]
        /// Optional: a cache written before this field existed has none.
        let sendingStopped: Bool?
    }

    private static func loadCache() -> Cache? {
        guard let data = KeychainStore.load(account: cacheAccount),
              let cache = try? JSONDecoder().decode(Cache.self, from: data) else { return nil }
        return cache
    }

    private func saveCache() {
        guard let data = try? JSONEncoder().encode(Cache(appliedAt: appliedAt, tokens: tokens, sendingStopped: sendingStopped)) else { return }
        // A failed write costs the next launch its instant first frame, and
        // nothing else: the list in memory is already correct, and the phone will
        // send again. Crashing or clearing the screen over it would be worse.
        _ = KeychainStore.save(data, account: Self.cacheAccount)
    }
}

// MARK: - WCSessionDelegate

/// `nonisolated` because `WCSessionDelegate`'s callbacks are not main-actor
/// isolated, while this type is (the module defaults to `MainActor`). Each one
/// hands its work back to the main actor rather than touching state off it.
extension WatchSessionModel: WCSessionDelegate {

    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        // The context the system was holding is delivered here, which is the
        // normal path on a cold launch. Activation has completed by the time this
        // runs, so `receivedApplicationContext` is meaningful already; it is
        // decoded here so that only the decoded, Sendable value crosses to the
        // main actor.
        let decoded = WatchTokenPayload.decode(applicationContext: session.receivedApplicationContext)
        Task { @MainActor in
            guard let decoded else { return }
            self.apply(decoded)
        }
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveApplicationContext applicationContext: [String: Any]) {
        let decoded = WatchTokenPayload.decode(applicationContext: applicationContext)
        Task { @MainActor in
            guard let decoded else { return }
            self.apply(decoded)
        }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // Read *now*. The system deletes the file as soon as this method returns,
        // so the bytes have to be in hand before handing anything to the main
        // actor — reading it inside the task below would read a file that is
        // already gone.
        let blob = try? Data(contentsOf: file.fileURL)
        Task { @MainActor in
            guard let blob else { return }
            self.apply(blob)
        }
    }
}

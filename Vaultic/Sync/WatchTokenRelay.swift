import Foundation
#if os(iOS)
import WatchConnectivity
#endif

/// The watch link, as `OTPDataStore` needs it: hand over the current token list.
///
/// Depending on this rather than on the `WatchConnectivity` type directly keeps
/// the store working unchanged on the Mac, which has no watch to talk to, and
/// lets a test drive the store without a paired watch — the same reasoning behind
/// `TokenSyncService`.
@MainActor
protocol WatchTokenRelayService: AnyObject {
    /// Offers the token list to the watch. The order given is the order the watch
    /// shows them in.
    ///
    /// Cheap to call with an unchanged list, and safe to call before the watch is
    /// reachable: the last offer is remembered and sent when it can be.
    func push(_ tokens: [OTPCode])
}

/// The relay for a platform with no watch. Every call is inert.
@MainActor
final class DisabledWatchTokenRelay: WatchTokenRelayService {
    func push(_ tokens: [OTPCode]) {}
}

/// Builds the relay this platform actually has.
@MainActor
enum WatchTokenRelay {
    /// The real relay on iPhone, an inert one everywhere else.
    ///
    /// Only iOS has a watch to talk to, but `OTPDataStore` is built on every
    /// platform, so picking here is what keeps a `#if` out of the store.
    ///
    /// ### When the watch gets codes at all
    /// Only when the watch app is installed on a paired watch (`isPaired` &&
    /// `isWatchAppInstalled`) *and* "Send codes to Apple Watch" is on. Installing
    /// the app used to be the only opt-in, but watchOS can install it
    /// automatically, so it was no real choice. The switch is in Settings and on
    /// the onboarding privacy page. Turning it off sends an empty list, which
    /// removes the codes from the watch.
    /// Whether this device can have an Apple Watch at all — an iPhone. Decides
    /// whether the "Send codes to Apple Watch" switch is shown.
    static var deviceCanPairWatch: Bool {
        #if os(iOS)
        WCSession.isSupported()
        #else
        false
        #endif
    }

    static func make() -> WatchTokenRelayService {
        #if os(iOS)
        return WatchConnectivityTokenRelay()
        #else
        return DisabledWatchTokenRelay()
        #endif
    }
}

/// What the watch is sent for a list, given the "Send codes to Apple Watch"
/// switch. Apart from the relay so the rule is asserted without a paired watch.
nonisolated struct WatchRelayOutgoing: Equatable, Sendable {
    let tokens: [OTPCode]
    /// Set with an empty list when sending is off: the empty list is what
    /// removes the codes the watch already holds, and the flag is how the watch
    /// knows to say "Turned Off" rather than "No Codes".
    let sendingStopped: Bool

    init(tokens: [OTPCode], sendingEnabled: Bool) {
        self.tokens = sendingEnabled ? tokens : []
        sendingStopped = !sendingEnabled
    }
}

/// The files an oversized token list is staged in for `transferFile`.
///
/// Separate from the relay so it can be tested without a paired watch: these
/// two steps are what decide how long a plaintext copy of every secret sits on
/// disk, and how well it is protected while it does.
nonisolated enum WatchRelayStaging {
    /// Writes one staged payload and returns its URL.
    ///
    /// The file holds every secret in plain JSON, so it is protected rather than
    /// left at the default class, which can be read whenever the phone has been
    /// unlocked once since it started. "Unless open" rather than "complete":
    /// `transferFile` keeps reading in the background, and a transfer that has
    /// already opened the file must be able to finish if the phone locks
    /// part-way through.
    static func write(_ payload: Data, in directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("tokens-\(UUID().uuidString).json")
        try payload.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        return url
    }

    /// Deletes staged files no transfer is still reading.
    ///
    /// `inFlight` is `nil` when the transfers in progress can't be known (the
    /// session isn't activated yet). Nothing is deleted then, because every
    /// staged file would otherwise look finished.
    static func prune(_ directory: URL, keeping inFlight: Set<URL>?) {
        guard let inFlight else { return }
        let keep = Set(inFlight.map(\.standardizedFileURL))
        let staged = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []

        for url in staged where !keep.contains(url.standardizedFileURL) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

#if os(iOS)

import WatchConnectivity

/// Sends the token list to the paired Apple Watch over `WCSession`.
///
/// ### Why an application context, and not a message
/// `updateApplicationContext` is the one `WCSession` transport that describes
/// *state* rather than events. It keeps only the newest dictionary, delivers it
/// whenever the watch app is next reachable — running or not — and leaves it
/// there for the watch to read on its next launch. A token list is exactly that
/// shape: a burst of edits while the user is in the app should arrive as one
/// current list, not as a queue of twenty stale ones.
///
/// ### Why there is a second transport
/// An application context is capped in size and the system rejects an oversized
/// one outright rather than truncating it. A very large token list would therefore
/// silently never reach the watch. Past the cap this hands over a file instead —
/// and because both transports carry the same `sentAt` stamp
/// (`WatchTokenPayload`), the watch applies whichever it sees last and cannot be
/// rolled back by the two arriving out of order.
@MainActor
final class WatchConnectivityTokenRelay: NSObject, WatchTokenRelayService {

    private let session: WCSession?

    /// The newest list offered, whether or not it could be sent when it arrived.
    ///
    /// Needed because `push` runs long before the session is active — the store
    /// pushes from its own `init` — so there has to be something to send when
    /// activation finally completes.
    private var latestTokens: [OTPCode]?

    /// What the watch was last sent, so an unchanged list is not re-sent on
    /// every save. Cleared whenever the set of paired watches changes, because
    /// "already sent" says nothing about a watch that was not there at the time.
    private var lastSent: WatchRelayOutgoing?

    /// Whether "Send codes to Apple Watch" is on.
    static var isSendingEnabled: Bool {
        UserDefaults.standard.object(forKey: AppPreferences.sendCodesToWatchKey) as? Bool
            ?? AppPreferences.sendCodesToWatchDefault
    }

    /// Re-offers the list when the switch changes, so turning it off clears the
    /// watch straight away rather than at the next edit.
    private var settingObserver: NSObjectProtocol?

    /// Where an oversized payload is staged for `transferFile`.
    private var stagingDirectory: URL { FileManager.default.temporaryDirectory.appendingPathComponent("WatchRelay", isDirectory: true) }

    /// Fires whenever the app comes forward, to re-offer the list.
    ///
    /// This is not belt-and-braces; it is the *only* reliable re-offer. The store
    /// pushes from its own `init`, which runs before `WCSession` has activated, so
    /// that first offer is always deferred — and the thing that would normally
    /// pick a deferred offer up is `activationDidCompleteWith`, a delegate
    /// callback that is not guaranteed to arrive (it was observed to never arrive
    /// on some launches, which left the watch on whatever it already had with no
    /// sign anything was wrong). Foregrounding is a moment the system definitely
    /// delivers, and the app foregrounds immediately after launch, so re-offering
    /// here means a send can never be dropped just because a callback did not come.
    private var foregroundObserver: NSObjectProtocol?

    override init() {
        session = WCSession.isSupported() ? WCSession.default : nil
        super.init()

        // `WCSession.delegate` is a weak reference, so this object has to be held
        // by someone. `OTPDataStore` holds it for the life of the app.
        session?.delegate = self
        session?.activate()

        // Never removed: this object lives as long as the app does.
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: AppActivity.didBecomeActive,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.pruneFinishedTransfers()
                self?.sendIfPossible()
            }
        }

        // Fires for every key; `sendIfPossible` returns early when nothing it
        // would send has changed, so the rest cost a comparison.
        settingObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.sendIfPossible() }
        }
    }

    func push(_ tokens: [OTPCode]) {
        latestTokens = tokens
        sendIfPossible()
    }

    // MARK: - Sending

    private func sendIfPossible() {
        guard let tokens = latestTokens else { return }
        guard let session else { return }

        // Activation is asynchronous and starts in `init`, so the offer made
        // during launch always lands here first. Nudging rather than returning
        // quietly means the list is not dropped: the next offer — which the
        // foreground observer guarantees — will find an activated session.
        guard session.activationState == .activated else {
            session.activate()
            return
        }

        // Nothing to send to until a watch is paired *and* the watch app is
        // installed. This is what makes installing the watch app the opt-in.
        guard session.isPaired, session.isWatchAppInstalled else { return }

        // Sending turned off sends an empty list: that is what removes the
        // codes the watch already holds.
        let outgoing = WatchRelayOutgoing(tokens: tokens, sendingEnabled: Self.isSendingEnabled)
        guard outgoing != lastSent else { return }

        let sentAt = Date()

        // Whatever list is still queued as a file is older than this one. File
        // transfers are queued and can land after a later context, and the watch
        // can't always tell them apart by stamp — after the phone's clock was
        // set back, an older list carries the later time. So the old ones are
        // withdrawn rather than left to arrive. See `WatchTokenPayload.isNewer`.
        session.outstandingFileTransfers.forEach { $0.cancel() }

        if let context = WatchTokenPayload.applicationContext(for: outgoing.tokens, sentAt: sentAt,
                                                              sendingStopped: outgoing.sendingStopped) {
            do {
                try session.updateApplicationContext(context)
                lastSent = outgoing
            } catch {
                #if DEBUG
                print("Watch relay: application context failed: \(error.localizedDescription)")
                #endif
            }
            return
        }

        sendAsFile(outgoing, sentAt: sentAt, over: session)
    }

    /// The oversized path: too many codes to fit an application context.
    ///
    /// A distinct file per send, and the directory is pruned only of transfers
    /// that have *finished* — `transferFile` reads the file in the background, so
    /// deleting one out from under a transfer in progress would fail it.
    private func sendAsFile(_ outgoing: WatchRelayOutgoing, sentAt: Date, over session: WCSession) {
        do {
            pruneFinishedTransfers()
            let payload = try WatchTokenPayload.encode(outgoing.tokens, sentAt: sentAt,
                                                       sendingStopped: outgoing.sendingStopped)
            let url = try WatchRelayStaging.write(payload, in: stagingDirectory)

            // The transfer object is deliberately not kept: it reports progress
            // and failure, and there is nothing useful to do with either. The list
            // is re-offered on the next edit, on the next launch, and whenever the
            // set of paired watches changes.
            _ = session.transferFile(url, metadata: nil)
            lastSent = outgoing
        } catch {
            #if DEBUG
            print("Watch relay: file transfer failed: \(error.localizedDescription)")
            #endif
        }
    }

    /// Deletes staged files no transfer is still reading.
    ///
    /// This is the only safe way to clean up after `transferFile`: it has no
    /// completion callback, but `outstandingFileTransfers` is exactly the set of
    /// files still in flight, so anything not in it can go.
    ///
    /// Runs on every foreground as well as before each send, so a finished
    /// transfer's plaintext copy doesn't sit around until the next large send.
    private func pruneFinishedTransfers() {
        // Without an activated session `outstandingFileTransfers` can't be read.
        let inFlight = session.flatMap { session in
            session.activationState == .activated
                ? Set(session.outstandingFileTransfers.map(\.file.fileURL))
                : nil
        }
        WatchRelayStaging.prune(stagingDirectory, keeping: inFlight)
    }
}

// MARK: - WCSessionDelegate

/// `nonisolated` because `WCSessionDelegate`'s callbacks are not main-actor
/// isolated while this type is (the module defaults to `MainActor`). Each one
/// hands its work back to the main actor rather than touching state off it.
extension WatchConnectivityTokenRelay: WCSessionDelegate {

    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        Task { @MainActor in
            self.sendIfPossible()
        }
    }

    /// The watch app was installed, removed, or a different watch was paired.
    ///
    /// What the previous watch was sent says nothing about this one, so the record
    /// of it is dropped and the current list goes out again. Without this, a user
    /// who installs the watch app *after* the phone has already pushed would see
    /// an empty watch until they happened to edit a token.
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.lastSent = nil
            self.sendIfPossible()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        // The user is switching to a different watch. Nothing to do here —
        // `sessionDidDeactivate` follows and re-activates.
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Required on iOS: a deactivated session never delivers again, so it has to
        // be re-activated for the relay to follow the user to their new watch. The
        // "already sent" record is dropped for the same reason as above.
        Task { @MainActor in
            self.lastSent = nil
            self.session?.activate()
        }
    }
}

#endif

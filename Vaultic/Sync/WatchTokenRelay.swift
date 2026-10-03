import Foundation

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
    /// There is no "send codes to my watch" setting, because installing the watch
    /// app *is* the opt-in: the phone only sends to a watch it reports as paired
    /// with the app installed (`isPaired` && `isWatchAppInstalled`), so a user who
    /// has not chosen to put Autheris on their wrist never has a secret leave the
    /// phone. That is the same spirit as iCloud Sync being off until asked for —
    /// with the request made by installing the app rather than by flipping a
    /// switch.
    static func make() -> WatchTokenRelayService {
        #if os(iOS)
        return WatchConnectivityTokenRelay()
        #else
        return DisabledWatchTokenRelay()
        #endif
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

    /// The list the watch was last sent, so an unchanged list is not re-sent on
    /// every save. Cleared whenever the set of paired watches changes, because
    /// "already sent" says nothing about a watch that was not there at the time.
    private var lastSentTokens: [OTPCode]?

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

        guard tokens != lastSentTokens else { return }

        let sentAt = Date()

        if let context = WatchTokenPayload.applicationContext(for: tokens, sentAt: sentAt) {
            do {
                try session.updateApplicationContext(context)
                lastSentTokens = tokens
            } catch {
                #if DEBUG
                print("Watch relay: application context failed: \(error.localizedDescription)")
                #endif
            }
            return
        }

        sendAsFile(tokens, sentAt: sentAt, over: session)
    }

    /// The oversized path: too many codes to fit an application context.
    ///
    /// A distinct file per send, and the directory is pruned only of transfers
    /// that have *finished* — `transferFile` reads the file in the background, so
    /// deleting one out from under a transfer in progress would fail it.
    private func sendAsFile(_ tokens: [OTPCode], sentAt: Date, over session: WCSession) {
        do {
            try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
            pruneFinishedTransfers()

            // The file holds every secret in plain JSON, so it is protected
            // rather than left at the default class, which can be read whenever the
            // phone has been unlocked once since it started. "Unless open" rather
            // than "complete": `transferFile` keeps reading in the background, and
            // a transfer that has already opened the file must be able to finish if
            // the phone locks part-way through.
            let url = stagingDirectory.appendingPathComponent("tokens-\(UUID().uuidString).json")
            try WatchTokenPayload.encode(tokens, sentAt: sentAt)
                .write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])

            // The transfer object is deliberately not kept: it reports progress
            // and failure, and there is nothing useful to do with either. The list
            // is re-offered on the next edit, on the next launch, and whenever the
            // set of paired watches changes.
            _ = session.transferFile(url, metadata: nil)
            lastSentTokens = tokens
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
        // Without an activated session `outstandingFileTransfers` can't be read,
        // and every staged file would look finished.
        guard let session, session.activationState == .activated else { return }
        let inFlight = Set(session.outstandingFileTransfers.map { $0.file.fileURL.standardizedFileURL })
        let staged = (try? FileManager.default.contentsOfDirectory(
            at: stagingDirectory,
            includingPropertiesForKeys: nil
        )) ?? []

        for url in staged where !inFlight.contains(url.standardizedFileURL) {
            try? FileManager.default.removeItem(at: url)
        }
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
            self.lastSentTokens = nil
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
            self.lastSentTokens = nil
            session.activate()
        }
    }
}

#endif

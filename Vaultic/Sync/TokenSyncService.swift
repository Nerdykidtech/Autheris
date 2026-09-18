import Foundation

/// The iCloud transport used by `OTPDataStore`.
///
/// Depending on this protocol rather than on `CloudKitTokenSyncService` directly
/// keeps three things possible: the store works unchanged when sync is off, tests
/// can drive the merge path with a fake, and an unavailable CloudKit environment
/// degrades to a no-op instead of a crash.
@MainActor
protocol TokenSyncService: AnyObject {
    /// Whether the user has turned sync on.
    var isEnabled: Bool { get }
    var status: CloudSyncStatus { get }
    /// Whether iCloud is actually usable right now (account signed in, entitlements present).
    var isAvailable: Bool { get }
    var onStatusChange: ((CloudSyncStatus) -> Void)? { get set }

    func refreshAvailability() async
    func setEnabled(_ enabled: Bool)

    /// Runs a full two-way sync against the private database.
    ///
    /// Returns the merge outcome when a merge ran, or `nil` when no work was
    /// possible (disabled, already syncing, or an error already reported through
    /// `status`). Callers apply the outcome to their local state.
    func sync(local: SyncLocalState) async -> SyncMergeOutcome?

    /// Deletes every record this app owns in the private database. Local tokens
    /// are never touched by this call.
    func deleteRemoteRecords() async throws

    /// Interprets a silent push payload. Returns `true` when it was a sync
    /// notification, meaning the caller should run `sync(local:)`.
    func handleRemoteNotification(userInfo: [AnyHashable: Any]) -> Bool
}

/// Stand-in used when no sync backend should exist. Every call is inert, status
/// stays `.disabled`, and iCloud is never touched — which is what makes an
/// unavailable CloudKit environment a non-event rather than a crash.
@MainActor
final class DisabledTokenSyncService: TokenSyncService {
    var isEnabled: Bool { false }
    var status: CloudSyncStatus { .disabled }
    var isAvailable: Bool { false }
    var onStatusChange: ((CloudSyncStatus) -> Void)?

    func refreshAvailability() async {}
    func setEnabled(_ enabled: Bool) {}
    func sync(local: SyncLocalState) async -> SyncMergeOutcome? { nil }
    func deleteRemoteRecords() async throws {}
    func handleRemoteNotification(userInfo: [AnyHashable: Any]) -> Bool { false }
}

/// Routes silent pushes from `AppDelegate` to whichever `OTPDataStore` is live.
///
/// `AppDelegate` is created by SwiftUI before the store and has no reference to
/// it, and a reaching-into-the-store global would be worse than this one tiny
/// seam. The store registers itself on creation.
@MainActor
enum SyncRemoteNotificationRouter {
    private static var handler: (([AnyHashable: Any]) async -> Bool)?

    static func register(_ handler: @escaping ([AnyHashable: Any]) async -> Bool) {
        self.handler = handler
    }

    /// Returns `true` when a sync service consumed the payload. Awaited so the
    /// caller can report the real background-fetch result to the system.
    static func deliver(userInfo: [AnyHashable: Any]) async -> Bool {
        guard let handler else { return false }
        return await handler(userInfo)
    }
}

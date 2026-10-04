import Foundation

/// The observable state of iCloud sync.
///
/// Kept intentionally small: Settings renders `title` and `detail`, and picks an
/// icon from `systemImage`. Because every `switch` over this type must be
/// exhaustive, adding a case forces the UI to be updated with it.
nonisolated enum CloudSyncStatus: Equatable {
    /// The user has not turned sync on.
    case disabled
    /// A sync is running now.
    case syncing
    /// Idle and up to date as of the given date (never synced yet when `nil`).
    case synced(Date?)
    /// No usable network. Sync resumes on its own; local edits are kept.
    case waitingForNetwork
    /// No iCloud account, or iCloud is restricted for this device.
    case accountUnavailable
    /// Sync cannot run in this build/environment, with the reason why.
    case unavailable(String)
    /// Something else went wrong.
    case failed(String)

    /// `String(localized:)` throughout, here and in `detail`: these reach the
    /// Settings row as `String`s, which `Text` shows as they are, so plain
    /// literals shipped in English in every language.
    var title: String {
        switch self {
        case .disabled: return String(localized: "iCloud Sync Off")
        case .syncing: return String(localized: "Syncing…")
        case .synced: return String(localized: "Synced")
        case .waitingForNetwork: return String(localized: "Sync Paused")
        case .accountUnavailable: return String(localized: "Sign in to iCloud")
        case .unavailable: return String(localized: "Sync unavailable")
        case .failed: return String(localized: "Sync error")
        }
    }

    /// Secondary line shown under the title, when there is something useful to say.
    var detail: String? {
        switch self {
        case .disabled:
            return String(localized: "Tokens are stored only on this device.")
        case .syncing:
            return nil
        case .synced(let date):
            guard let date else { return String(localized: "Waiting for first sync") }
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            return String(localized: "Last updated \(formatter.localizedString(for: date, relativeTo: Date()))")
        case .waitingForNetwork:
            return String(localized: "Will retry automatically. Changes are saved on this device.")
        case .accountUnavailable:
            return String(localized: "Sign in to iCloud in Settings to sync across your devices.")
        case .unavailable(let reason):
            return reason
        case .failed(let message):
            return message
        }
    }

    var systemImage: String {
        switch self {
        case .disabled: return "icloud.slash"
        case .syncing: return "arrow.triangle.2.circlepath.icloud"
        case .synced: return "checkmark.icloud"
        case .waitingForNetwork: return "icloud.slash"
        case .accountUnavailable: return "person.crop.circle.badge.exclamationmark"
        case .unavailable: return "exclamationmark.icloud"
        case .failed: return "exclamationmark.triangle"
        }
    }

    /// Drives the spinner. Only a running sync should look busy.
    var isBusy: Bool {
        if case .syncing = self { return true }
        return false
    }

    /// `true` when the user can usefully tap "Try Again".
    var allowsRetry: Bool {
        switch self {
        case .waitingForNetwork, .failed, .unavailable: return true
        case .disabled, .syncing, .synced, .accountUnavailable: return false
        }
    }

    /// `true` when the failure is about *this build's* configuration rather than a
    /// condition that will pass — the difference between "try again later" and
    /// "this will not work until the build is fixed".
    ///
    /// Settings uses it to avoid telling the user to wait for iCloud when the real
    /// problem is an entitlement the app does not have.
    var isConfigurationFailure: Bool {
        if case .unavailable = self { return true }
        return false
    }
}

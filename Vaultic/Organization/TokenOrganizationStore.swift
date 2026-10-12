import Foundation
import Observation

/// Keeps `TokenOrganization` on this device, saves it on every change, and tells
/// the data store when a local change should be synced.
///
/// It is only read when the user has folders turned on. While they are off nothing
/// here is shown, but the data is kept, so turning them off and on again does not
/// lose a folder layout.
@MainActor
@Observable
final class TokenOrganizationStore {
    /// The `@AppStorage` key for the Settings switch that turns folders on.
    /// Off by default: a user who never opens it sees the list as it always was.
    nonisolated static let enabledKey = "foldersEnabled"
    private nonisolated static let storageKey = "tokenOrganization"

    private(set) var organization: TokenOrganization
    private let defaults: UserDefaults
    /// Called after a change made on this device, so the data store can sync it.
    /// Not called for a copy adopted from iCloud, which would otherwise bounce back.
    var onLocalChange: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(TokenOrganization.self, from: data) {
            organization = saved
        } else {
            organization = TokenOrganization()
        }
    }

    /// Applies a change made on this device, stamps it, saves it, and asks for a sync.
    ///
    /// A change that leaves the organization as it was is not saved or stamped, so
    /// opening an editor and closing it does not rewrite anything.
    func update(_ change: (inout TokenOrganization) -> Void) {
        var next = organization
        change(&next)
        guard next != organization else { return }
        next.stamp(Date())
        organization = next
        save()
        onLocalChange?()
    }

    /// Replaces the organization with the copy from iCloud, when that copy is newer.
    /// The copy keeps its own timestamp, and nothing is sent back for it.
    func adoptRemote(_ remote: TokenOrganization) {
        guard remote != organization else { return }
        organization = remote
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(organization) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}

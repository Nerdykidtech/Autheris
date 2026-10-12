import Foundation
import Observation

/// Keeps `TokenOrganization` on this device, and saves it on every change.
///
/// It is only read when the user has folders turned on. While they are off
/// nothing here is shown, but the data is kept, so turning them off and on again
/// does not lose a folder layout.
@MainActor
@Observable
final class TokenOrganizationStore {
    /// The `@AppStorage` key for the Settings switch that turns folders on.
    /// Off by default: a user who never opens it sees the list as it always was.
    nonisolated static let enabledKey = "foldersEnabled"
    private nonisolated static let storageKey = "tokenOrganization"

    private(set) var organization: TokenOrganization
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(TokenOrganization.self, from: data) {
            organization = saved
        } else {
            organization = TokenOrganization()
        }
    }

    /// Applies a change and saves the result.
    ///
    /// A change that leaves the organization as it was is not saved, so opening an
    /// editor and closing it does not rewrite the stored copy.
    func update(_ change: (inout TokenOrganization) -> Void) {
        var next = organization
        change(&next)
        guard next != organization else { return }
        organization = next
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(organization) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}

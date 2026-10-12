import XCTest
@testable import Vaultic

/// A folder is a view over the token list, so the cases that matter are the ones
/// where a name, a delete or a filter could leave a token filed under a folder that
/// no longer exists, or hide a token that should show.
final class TokenOrganizationTests: XCTestCase {

    private func token(_ label: String) -> OTPCode {
        OTPCode(label: label, account: "acct", secret: "JBSWY3DPEHPK3PXP")
    }

    func testNamesAreTrimmedAndMustBeUniqueIgnoringCase() {
        var organization = TokenOrganization()
        XCTAssertEqual(organization.addFolder(named: "  Work  ")?.name, "Work")
        XCTAssertNil(organization.addFolder(named: "work"), "a folder name must be unique, ignoring case")
        XCTAssertNil(organization.addFolder(named: "   "), "a blank name is refused")
        XCTAssertNil(organization.addFolder(named: String(repeating: "x", count: TokenOrganization.maximumNameLength + 1)))
        XCTAssertNotNil(organization.addFolder(named: String(repeating: "x", count: TokenOrganization.maximumNameLength)))
        XCTAssertEqual(organization.folders.count, 2)
    }

    func testRenameKeepsTheNameUniqueAgainstOthersOnly() {
        var organization = TokenOrganization()
        let work = organization.addFolder(named: "Work")!
        _ = organization.addFolder(named: "Home")!
        XCTAssertTrue(organization.renameFolder(work.id, to: "work"), "renaming to its own name in a new case is allowed")
        XCTAssertFalse(organization.renameFolder(work.id, to: "Home"), "renaming onto another folder is refused")
        XCTAssertEqual(organization.folders.first { $0.id == work.id }?.name, "work")
    }

    func testDeletingAFolderLeavesItsTokensUnfiledAndTheTokensThemselves() {
        var organization = TokenOrganization()
        let folder = organization.addFolder(named: "Work")!
        let code = token("GitHub")
        organization.setFolder(folder.id, for: code.id)

        organization.deleteFolder(folder.id)

        XCTAssertNil(organization.folder(for: code.id))
        XCTAssertNil(organization.folderByToken[code.id], "no stale folder id is left behind")
    }

    func testSettingAFolderThatDoesNotExistFilesTheTokenUnderNothing() {
        var organization = TokenOrganization()
        let code = token("GitHub")
        organization.setFolder(UUID(), for: code.id)
        XCTAssertNil(organization.folderByToken[code.id])
    }

    func testFilterShowsOnlyTheSelectedFolder() {
        var organization = TokenOrganization()
        let work = organization.addFolder(named: "Work")!
        let github = token("GitHub")
        let game = token("Game")
        let bank = token("Bank")
        organization.setFolder(work.id, for: github.id)
        let all = [github, game, bank]

        XCTAssertEqual(organization.filter(all, by: .all).map(\.id), all.map(\.id))
        XCTAssertEqual(organization.filter(all, by: .folder(work.id)).map(\.id), [github.id])
        XCTAssertEqual(organization.count(inFolder: work.id), 1)
    }

    func testFilterKeepsTheOrderItWasGiven() {
        var organization = TokenOrganization()
        let folder = organization.addFolder(named: "Shared")!
        let first = token("First")
        let second = token("Second")
        organization.setFolder(folder.id, for: first.id)
        organization.setFolder(folder.id, for: second.id)
        XCTAssertEqual(organization.filter([second, first], by: .folder(folder.id)).map(\.id), [second.id, first.id])
    }

    func testAFilterOnADeletedFolderIsNoLongerContained() {
        var organization = TokenOrganization()
        let folder = organization.addFolder(named: "Work")!
        XCTAssertTrue(organization.contains(.folder(folder.id)))
        organization.deleteFolder(folder.id)
        XCTAssertFalse(organization.contains(.folder(folder.id)))
        XCTAssertTrue(organization.contains(.all))
    }

    func testOrganizationRoundTripsThroughCodable() throws {
        var organization = TokenOrganization()
        let folder = organization.addFolder(named: "Work")!
        let code = token("GitHub")
        organization.setFolder(folder.id, for: code.id)

        let data = try JSONEncoder().encode(organization)
        let decoded = try JSONDecoder().decode(TokenOrganization.self, from: data)

        XCTAssertEqual(decoded, organization)
    }

    @MainActor
    func testStoreSavesAChangeAndSkipsAnUnchangedOne() async throws {
        let suite = "TokenOrganizationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = TokenOrganizationStore(defaults: defaults)
        store.update { _ = $0.addFolder(named: "Work") }
        XCTAssertNotNil(defaults.data(forKey: "tokenOrganization"))

        let reloaded = TokenOrganizationStore(defaults: defaults)
        XCTAssertEqual(reloaded.organization.folders.map(\.name), ["Work"])

        store.update { _ in }
        XCTAssertEqual(store.organization.folders.count, 1)
    }
}

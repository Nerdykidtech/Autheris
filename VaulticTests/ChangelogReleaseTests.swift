import XCTest
@testable import Vaultic

/// Guards the version number against the changelog that describes it.
///
/// The app's marketing version lives in four build settings, its in-app changelog in
/// `ChangelogView`, the release notes in `CHANGELOG.md`, and the App Store copy in
/// `metadata/`. Nothing connected those before, so bumping the version without adding
/// its entry is a silent drift that ships: the app reports 2.2 while its own
/// changelog stops at 2.1, and the store listing still advertises the previous
/// release. These tests only cover the in-app half — the half a build can see.
// The app target defaults to main-actor isolation, which makes the types under
// test main-actor isolated too.
@MainActor
final class ChangelogReleaseTests: XCTestCase {

    private var marketingVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    /// The newest entry has to be the version actually being shipped. This is the
    /// assertion that would have caught a version bump with no release notes.
    func testTheNewestEntryIsTheVersionBeingShipped() {
        XCTAssertEqual(
            ChangelogRelease.catalog.first?.version,
            marketingVersion,
            "The newest changelog entry must match CFBundleShortVersionString — "
            + "bumping the version means adding its notes."
        )
    }

    func testTheCatalogIsNewestFirst() {
        // "2.10" must sort above "2.9", so compare the components, not the string.
        let numbers: [Double] = ChangelogRelease.catalog.compactMap { release in
            let parts = release.version.split(separator: ".").compactMap { Double($0) }
            guard parts.count == 2 else { return nil }
            return parts[0] + parts[1] / 100
        }

        XCTAssertEqual(
            numbers.count,
            ChangelogRelease.catalog.count,
            "every version must be of the form major.minor"
        )
        XCTAssertEqual(numbers, numbers.sorted(by: >), "the catalog must list newest first")
    }

    func testEveryReleaseHasNotesAndADate() {
        for release in ChangelogRelease.catalog {
            XCTAssertFalse(release.changes.isEmpty, "\(release.version) has no release notes")
            XCTAssertFalse(release.date.isEmpty, "\(release.version) has no date")
        }
    }
}

import XCTest
@testable import Vaultic

/// The grid's grabber finds a folder chip by where the pointer is, against the frames
/// the chips report. A point between chips, or outside them all, is no folder.
@MainActor
final class FolderDropTargetsTests: XCTestCase {

    func testAPointInsideAChipFindsItsFolder() async {
        let targets = FolderDropTargets()
        let work = UUID(), home = UUID()
        targets.frames[work] = CGRect(x: 100, y: 10, width: 80, height: 30)
        targets.frames[home] = CGRect(x: 190, y: 10, width: 80, height: 30)

        XCTAssertEqual(targets.folder(at: CGPoint(x: 120, y: 20)), work)
        XCTAssertEqual(targets.folder(at: CGPoint(x: 200, y: 25)), home)
    }

    func testAPointOutsideEveryChipFindsNothing() async {
        let targets = FolderDropTargets()
        targets.frames[UUID()] = CGRect(x: 100, y: 10, width: 80, height: 30)

        XCTAssertNil(targets.folder(at: CGPoint(x: 185, y: 20)), "between chips")
        XCTAssertNil(targets.folder(at: CGPoint(x: 120, y: 300)), "down in the grid")
    }
}

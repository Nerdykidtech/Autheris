import XCTest
@testable import Vaultic

/// The staged file an oversized token list is sent to the watch in.
///
/// It holds every secret in plain JSON, so what matters is how it is protected
/// and that it doesn't outlive its transfer. Both are file operations, so none of
/// this needs a paired watch.
final class WatchRelayStagingTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WatchRelayStagingTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func stage(_ text: String = "[]") throws -> URL {
        try WatchRelayStaging.write(Data(text.utf8), in: directory)
    }

    private func staged() -> Set<String> {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return Set(urls.map(\.lastPathComponent))
    }

    // MARK: - Writing

    func testTheStagedFileIsProtectedUnlessOpen() throws {
        #if targetEnvironment(simulator)
        // The simulator has no data protection and reports no protection class
        // for any file, so this can only be checked on a device.
        throw XCTSkip("File protection is only recorded on a device.")
        #else
        let url = try stage()

        let protection = try FileManager.default.attributesOfItem(atPath: url.path)[.protectionKey]
            as? FileProtectionType
        XCTAssertEqual(protection, .completeUnlessOpen)
        #endif
    }

    func testEachSendGetsItsOwnFileWithThePayloadInIt() throws {
        let first = try stage("one")
        let second = try stage("two")

        XCTAssertNotEqual(first, second, "a new send must not overwrite a file a transfer may still be reading")
        XCTAssertEqual(try Data(contentsOf: first), Data("one".utf8))
        XCTAssertEqual(try Data(contentsOf: second), Data("two".utf8))
    }

    // MARK: - Pruning

    func testPruningDeletesFinishedTransfersAndKeepsOnesInFlight() throws {
        let finished = try stage()
        let inFlight = try stage()

        WatchRelayStaging.prune(directory, keeping: [inFlight])

        XCTAssertEqual(staged(), [inFlight.lastPathComponent])
        XCTAssertFalse(FileManager.default.fileExists(atPath: finished.path))
    }

    func testPruningMatchesInFlightFilesWrittenWithADifferentPathSpelling() throws {
        let inFlight = try stage()
        // The session reports its own URL for the file, which needn't be spelled
        // the same way as the one the relay wrote.
        let respelled = URL(fileURLWithPath: directory.path + "/./" + inFlight.lastPathComponent)

        WatchRelayStaging.prune(directory, keeping: [respelled])

        XCTAssertEqual(staged(), [inFlight.lastPathComponent])
    }

    func testNothingIsPrunedWhileTheTransfersInFlightAreUnknown() throws {
        let url = try stage()

        WatchRelayStaging.prune(directory, keeping: nil)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testPruningAMissingDirectoryIsHarmless() {
        WatchRelayStaging.prune(directory, keeping: [])

        XCTAssertTrue(staged().isEmpty)
    }
}

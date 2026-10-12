import CoreGraphics
import Foundation
import Observation

/// Where the folder chips are on screen, so a drag that is not a system drag — the
/// grid's grabber — can still drop a token on one.
///
/// The chips report their frames here in global coordinates, and the grabber reports
/// which chip it is over, so that chip can show the same ring a system drag gives it.
@MainActor
@Observable
final class FolderDropTargets {
    /// Each chip's frame, in global coordinates, by folder id.
    var frames: [UUID: CGRect] = [:]
    /// The folder whose chip the grabber is over, or `nil`.
    var hoveredFolder: UUID?

    /// The folder whose chip contains `point`, a global position.
    func folder(at point: CGPoint) -> UUID? {
        frames.first { $0.value.contains(point) }?.key
    }
}

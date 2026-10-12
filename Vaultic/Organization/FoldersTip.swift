import SwiftUI
import TipKit

/// A tip on Home that offers Folders to someone who chose Not Now in the introduction.
///
/// TipKit decides when it shows and keeps that on the device. It shows only while
/// folders are off, and only after the introduction sheet has been seen.
struct FoldersTip: Tip {
    /// Mirrors the Folders switch, so the tip goes away once folders are on.
    @Parameter static var foldersAreOn: Bool = false
    /// Set once the introduction sheet has been seen, so the two never show together.
    @Parameter static var introSeen: Bool = false

    static let turnOnActionID = "turnOnFolders"

    var title: Text {
        Text("Sort with Folders")
    }

    var message: Text? {
        Text("Group your tokens into folders and filter the list with a tap.")
    }

    var image: Image? {
        Image(systemName: "folder")
    }

    var actions: [Action] {
        [Action(id: Self.turnOnActionID) { Text("Turn On Folders") }]
    }

    var rules: [Rule] {
        [
            #Rule(Self.$foldersAreOn) { $0 == false },
            #Rule(Self.$introSeen) { $0 == true },
        ]
    }
}

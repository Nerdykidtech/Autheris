import SwiftUI

/// Introduces Folders, once, to someone updating from a version without them.
///
/// Turning folders on here is the same as the switch in Settings; Not Now leaves them
/// off, and a tip on Home offers them again later (see `FoldersTip`).
struct FoldersIntroSheet: View {
    let onTurnOn: () -> Void
    let onNotNow: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            FoldersIntroDemo()
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(.background.secondary, in: .rect(cornerRadius: 20))

            VStack(spacing: 10) {
                Text("New: Folders")
                    .font(.title2.weight(.bold))
                Text("Sort your tokens into folders, give each one a colour, and filter your list with a tap. In Edit, drag a token onto a folder to file it. With iCloud Sync on, folders follow you to your other devices.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 12) {
                Button(action: onTurnOn) {
                    Text("Turn On Folders")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

                Button("Not Now", action: onNotNow)
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        #if os(macOS)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        #else
        .presentationDetents([.large])
        .interactiveDismissDisabled()
        #endif
    }
}

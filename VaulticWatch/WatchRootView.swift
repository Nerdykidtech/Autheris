import SwiftUI

/// What the watch shows: the codes, one screenful at a time.
struct WatchRootView: View {
    @ObservedObject var session: WatchSessionModel

    var body: some View {
        if session.tokens.isEmpty {
            WatchEmptyView(hasReceivedPayload: session.hasReceivedPayload)
        } else {
            // One code per screen, scrolling vertically between them.
            //
            // `verticalPage` rather than a `List`. A list on a watch is still a
            // list of rows and every row fights the others for a very narrow
            // screen; a page per code makes the code the whole screen and lets it
            // be read at a glance, which is the only reason anyone opens this app.
            // It also gets the Digital Crown for free — turning it steps between
            // codes, which is the gesture the hardware is already good at.
            TabView {
                ForEach(session.tokens) { token in
                    WatchCodePageView(token: token)
                }
            }
            .tabViewStyle(.verticalPage)
        }
    }
}

/// Shown when there is nothing to display.
///
/// The two reasons for an empty screen are different and are said differently: a
/// user whose phone has no codes needs to add one, and a user whose phone has not
/// spoken yet needs to wait a moment. Showing the same words for both would send
/// half of them looking for a problem that is not there.
private struct WatchEmptyView: View {
    let hasReceivedPayload: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: hasReceivedPayload ? "key" : "iphone")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text(hasReceivedPayload ? "No Codes" : "Not Synced Yet")
                .font(.headline)

            Text(hasReceivedPayload
                 ? "Add a code in Autheris on your iPhone and it will appear here."
                 : "Open Autheris on your iPhone to send your codes to this watch.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal)
    }
}

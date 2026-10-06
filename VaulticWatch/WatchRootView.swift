import SwiftUI

/// What the watch shows: the codes, one screenful at a time.
struct WatchRootView: View {
    @ObservedObject var session: WatchSessionModel

    var body: some View {
        if session.tokens.isEmpty {
            WatchEmptyView(hasReceivedPayload: session.hasReceivedPayload,
                           sendingStopped: session.sendingStopped)
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
    /// A third reason: the iPhone has stopped sending, and said so.
    let sendingStopped: Bool

    private var symbol: String {
        sendingStopped ? "applewatch.slash" : hasReceivedPayload ? "key" : "iphone"
    }

    private var title: LocalizedStringKey {
        sendingStopped ? "Turned Off" : hasReceivedPayload ? "No Codes" : "Not Synced Yet"
    }

    private var message: LocalizedStringKey {
        if sendingStopped {
            return "Turn on Send codes to Apple Watch in Autheris on your iPhone to see your codes here."
        }
        return hasReceivedPayload
            ? "Add a code in Autheris on your iPhone and it will appear here."
            : "Open Autheris on your iPhone to send your codes to this watch."
    }

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)

            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal)
    }
}

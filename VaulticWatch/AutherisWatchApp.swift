import SwiftUI

@main
struct AutherisWatchApp: App {
    /// Owned here rather than by the root view.
    ///
    /// `WCSession` is a process-wide singleton with exactly one delegate, so the
    /// object that receives the phone's token list has to outlive any particular
    /// view; a `@StateObject` on the root view would be recreated whenever SwiftUI
    /// decided to, and the delegate would go with it.
    @StateObject private var session = WatchSessionModel()

    var body: some Scene {
        WindowGroup {
            WatchRootView(session: session)
        }
    }
}

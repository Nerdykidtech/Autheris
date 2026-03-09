import SwiftUI

@main
struct VaulticApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    
    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                ContentView() // Your existing main app view
            } else {
                WelcomeView()
            }
        }
    }
}

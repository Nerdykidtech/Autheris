import SwiftUI

@main
struct AutherisApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @StateObject private var dataStore = OTPDataStore()
    @State private var showingImportSheet = false
    @State private var importData: Data?
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                if hasCompletedOnboarding {
                    ContentView()
                        .environmentObject(dataStore)
                        .onOpenURL { url in
                            print("ContentView received URL: \(url.absoluteString)")
                            handleIncomingURL(url)
                        }
                } else {
                    WelcomeView()
                }
                
                // Import sheet overlay - shows on top of everything
                if showingImportSheet {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .ignoresSafeArea()
                        .overlay(Color.black.opacity(0.25))
                        .transition(.opacity)
                    
                    if let data = importData {
                        ImportConfirmationView(data: data, dataStore: dataStore, isPresented: $showingImportSheet)
                            .transition(.scale.combined(with: .opacity))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.3), value: showingImportSheet)
            .animation(.easeInOut(duration: 0.3), value: hasCompletedOnboarding)
            .onAppear {
                print("App appeared, hasCompletedOnboarding: \(hasCompletedOnboarding)")
                // Check for pending import data
                if let data = UserDefaults.standard.data(forKey: "pendingImportData") {
                    print("Found pending import data on app appear")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        importData = data
                        showingImportSheet = true
                        UserDefaults.standard.removeObject(forKey: "pendingImportData")
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("AutherisImportData"))) { notification in
                print("Received import data notification")
                if let data = notification.object as? Data {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        importData = data
                        showingImportSheet = true
                    }
                }
            }
        }
    }
    
    private func handleIncomingURL(_ url: URL) {
        print("Handling incoming URL: \(url.absoluteString)")
        
        guard url.scheme == "autheris" && url.host == "import" else {
            print("Not an autheris import URL")
            return
        }
        
        print("Processing autheris import URL...")
        
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let queryItems = components.queryItems,
           let dataString = queryItems.first(where: { $0.name == "data" })?.value {
            
            print("Found data string in URL, length: \(dataString.count)")
            
            // Convert URL-safe Base64 back to standard Base64
            let standardBase64String = dataString
                .replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")
            
            // Add padding if needed
            var paddedBase64String = standardBase64String
            let paddingLength = (4 - (standardBase64String.count % 4)) % 4
            if paddingLength > 0 {
                paddedBase64String = standardBase64String + String(repeating: "=", count: paddingLength)
            }
            
            print("Decoding Base64 data...")
            
            if let data = Data(base64Encoded: paddedBase64String) {
                print("Successfully decoded data, size: \(data.count) bytes")
                
                // Store and show the import sheet
                importData = data
                showingImportSheet = true
            } else {
                print("Failed to decode Base64 data")
            }
        } else {
            print("No data parameter found in URL")
        }
    }
}

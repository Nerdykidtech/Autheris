import SwiftUI

@main
struct AutherisApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("enablePrivacyBlur") private var enablePrivacyBlur = true
    @AppStorage("hideCodesInAppSwitcher") private var hideCodesInAppSwitcher = true
    @StateObject private var dataStore = OTPDataStore()
    @State private var showingImportSheet = false
    @State private var importData: Data?
    @State private var isAppActive = true
    @State private var showPrivacyOverlay = false
    
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
                        .blur(radius: enablePrivacyBlur && !isAppActive ? 10 : 0)
                        .opacity(enablePrivacyBlur && !isAppActive ? 0.7 : 1)
                } else {
                    WelcomeView()
                        .blur(radius: enablePrivacyBlur && !isAppActive ? 10 : 0)
                        .opacity(enablePrivacyBlur && !isAppActive ? 0.7 : 1)
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
                
                // Privacy overlay for app switcher and when backgrounded
                if showPrivacyOverlay && hideCodesInAppSwitcher {
                    PrivacyOverlay()
                        .transition(.opacity)
                        .zIndex(1) // Ensure it's on top
                }
            }
            .animation(.easeInOut(duration: 0.3), value: showingImportSheet)
            .animation(.easeInOut(duration: 0.3), value: hasCompletedOnboarding)
            .animation(.easeInOut(duration: 0.3), value: isAppActive)
            .animation(.easeInOut(duration: 0.3), value: showPrivacyOverlay)
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
                
                // Set up app state observers
                setupAppStateObservers()
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
            .onChange(of: isAppActive) { oldValue, newValue in
                print("App active state changed: \(newValue)")
                // Update privacy overlay based on app state and settings
                updatePrivacyOverlay()
            }
            .onChange(of: hideCodesInAppSwitcher) { oldValue, newValue in
                // Update privacy overlay when setting changes
                updatePrivacyOverlay()
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
    
    private func setupAppStateObservers() {
        // Observe app state changes
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            print("App will resign active")
            isAppActive = false
            updatePrivacyOverlay()
        }
        
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            print("App did become active")
            isAppActive = true
            updatePrivacyOverlay()
        }
        
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            print("App did enter background")
            isAppActive = false
            updatePrivacyOverlay()
        }
        
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            print("App will enter foreground")
            isAppActive = true
            updatePrivacyOverlay()
        }
    }
    
    private func updatePrivacyOverlay() {
        // Show privacy overlay when app is not active AND the setting is enabled
        showPrivacyOverlay = !isAppActive && hideCodesInAppSwitcher
        print("Privacy overlay: \(showPrivacyOverlay), isAppActive: \(isAppActive), hideCodesInAppSwitcher: \(hideCodesInAppSwitcher)")
    }
}

// MARK: - Privacy Overlay View
struct PrivacyOverlay: View {
    var body: some View {
        ZStack {
            // Blurred background
            Rectangle()
                .fill(.ultraThickMaterial)
                .ignoresSafeArea()
            
            // Privacy message (centered)
            VStack(spacing: 16) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.accentColor)
                    .symbolRenderingMode(.hierarchical)
                
                Text("Autheris")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Text("Protected by Privacy Mode")
                    .font(.system(size: 16, weight: .medium, design: .default))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }
}


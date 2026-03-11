import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        print("Autheris app launched")
        
        // Clear any old pending data
        UserDefaults.standard.removeObject(forKey: "pendingImportData")
        UserDefaults.standard.synchronize()
        
        return true
    }
    
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        print("App opened with URL: \(url.absoluteString)")
        
        guard url.scheme == "autheris" && url.host == "import" else {
            print("Not an autheris import URL, ignoring")
            return false
        }
        
        print("Processing import URL...")
        
        // Extract data from URL
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let queryItems = components.queryItems,
           let dataString = queryItems.first(where: { $0.name == "data" })?.value {
            
            print("Found data parameter, length: \(dataString.count)")
            
            // Convert URL-safe Base64
            let standardBase64String = dataString
                .replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")
            
            // Add padding
            var paddedBase64String = standardBase64String
            let paddingLength = (4 - (standardBase64String.count % 4)) % 4
            if paddingLength > 0 {
                paddedBase64String = standardBase64String + String(repeating: "=", count: paddingLength)
            }
            
            if let data = Data(base64Encoded: paddedBase64String) {
                print("Successfully decoded data: \(data.count) bytes")
                
                // Store in UserDefaults
                UserDefaults.standard.set(data, forKey: "pendingImportData")
                UserDefaults.standard.synchronize()
                
                // Post notification
                NotificationCenter.default.post(
                    name: Notification.Name("AutherisImportData"),
                    object: data
                )
                
                return true
            }
        }
        
        return false
    }
}

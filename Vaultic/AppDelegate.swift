import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        #if DEBUG
        print("Autheris app launched")
        #endif
        
        // Clear any old pending data
        UserDefaults.standard.removeObject(forKey: "pendingImportData")
        UserDefaults.standard.synchronize()
        
        return true
    }
}

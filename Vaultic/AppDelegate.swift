import CloudKit
import Foundation

#if os(iOS)
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        #if DEBUG
        print("Autheris app launched")
        #endif

        clearPendingImport()

        // Silent pushes carry iCloud sync changes. Registering unconditionally is
        // harmless: nothing is delivered until a CloudKit subscription exists, and
        // that is only created once the user turns sync on.
        application.registerForRemoteNotifications()

        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        #if DEBUG
        print("Registered for remote notifications")
        #endif
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        #if DEBUG
        print("Remote notification registration failed: \(error.localizedDescription)")
        #endif
    }

    /// Silent push from the sync service's `CKDatabaseSubscription`, so a change
    /// made on another device is applied without the user reopening the app.
    ///
    /// The sync is awaited before calling the completion handler, so the system is
    /// told what actually happened instead of being told "new data" optimistically.
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        Task { @MainActor in
            let handled = await SyncRemoteNotificationRouter.deliver(userInfo: userInfo)
            completionHandler(handled ? .newData : .noData)
        }
    }
}

#else
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        print("Autheris app launched")
        #endif

        clearPendingImport()

        // Same reasoning as on iOS: registering unconditionally is harmless until
        // a CloudKit subscription exists, and that only happens once the user
        // turns sync on.
        NSApplication.shared.registerForRemoteNotifications()
    }

    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        #if DEBUG
        print("Registered for remote notifications")
        #endif
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        #if DEBUG
        print("Remote notification registration failed: \(error.localizedDescription)")
        #endif
    }

    /// Silent push from the sync service's `CKDatabaseSubscription`.
    ///
    /// macOS delivers this without a completion handler — there is no background
    /// fetch budget to report against the way iOS has one, because the app is
    /// either running or it is not — so the sync is simply awaited, and there is
    /// no one to tell what it found.
    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        // `deliver` takes the iOS spelling of the payload dictionary; rebuilding
        // it is the only difference between the two platform callbacks.
        let payload = Dictionary(
            uniqueKeysWithValues: userInfo.map { (AnyHashable($0.key), $0.value) }
        )
        Task { @MainActor in
            _ = await SyncRemoteNotificationRouter.deliver(userInfo: payload)
        }
    }
}
#endif

private func clearPendingImport() {
    // Clear any old pending data. Shared by both platforms: the `autheris://import`
    // URL that sets this key is registered on both.
    UserDefaults.standard.removeObject(forKey: "pendingImportData")
    UserDefaults.standard.synchronize()
}

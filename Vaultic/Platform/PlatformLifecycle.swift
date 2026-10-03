import Foundation

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The app-activation notifications, under one set of names.
///
/// The two platforms carve up the same idea differently. iOS separates
/// *inactive* (interrupted, running, still on screen) from *background*
/// (switched away). macOS separates *inactive* from *hidden* (⌘H, or the last
/// window closed). For this app the four mean exactly the same two things: the
/// code list may be visible to someone the user did not intend, or it may not.
///
/// Naming the correspondence here rather than at the observer means the privacy
/// logic reads the same on both platforms, which is the point — it is the same
/// logic, and it is covered by the same tests.
enum AppActivity {

    /// The app is about to stop being the frontmost app: the app switcher is
    /// appearing, or another window has taken focus.
    static var willResignActive: Notification.Name {
        #if os(macOS)
        NSApplication.willResignActiveNotification
        #else
        UIApplication.willResignActiveNotification
        #endif
    }

    static var didBecomeActive: Notification.Name {
        #if os(macOS)
        NSApplication.didBecomeActiveNotification
        #else
        UIApplication.didBecomeActiveNotification
        #endif
    }

    /// The moments a launch that found the Keychain locked should read it again:
    /// the device being unlocked, and the app coming to the front. macOS posts
    /// no unlock notification to apps, so there it is only the second.
    static var keychainMayHaveBecomeReadable: [Notification.Name] {
        #if os(macOS)
        [NSApplication.didBecomeActiveNotification]
        #else
        [UIApplication.protectedDataDidBecomeAvailableNotification,
         UIApplication.didBecomeActiveNotification]
        #endif
    }

    /// The app is no longer on screen at all: backgrounded on iOS, hidden on the
    /// Mac.
    static var didLeaveForeground: Notification.Name {
        #if os(macOS)
        NSApplication.didHideNotification
        #else
        UIApplication.didEnterBackgroundNotification
        #endif
    }

    static var willEnterForeground: Notification.Name {
        #if os(macOS)
        NSApplication.didUnhideNotification
        #else
        UIApplication.willEnterForegroundNotification
        #endif
    }

    /// Fires when the screen starts or stops being recorded or mirrored.
    ///
    /// iOS only — there is no macOS equivalent, which is exactly why the Mac
    /// protects the window structurally instead. `nil` on macOS so the observer
    /// for it can be skipped rather than being a notification that never arrives.
    static var screenCaptureChanged: Notification.Name? {
        #if os(macOS)
        nil
        #else
        UIScreen.capturedDidChangeNotification
        #endif
    }
}

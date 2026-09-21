import Foundation

/// Decides when token content has to be hidden from something other than the
/// user, and how much hiding the situation calls for.
///
/// There are two independent ways the app can be observed:
///
/// 1. It stops being the frontmost app — the app switcher and the home screen.
///    This is what the existing background/foreground notifications catch.
/// 2. Its screen starts being recorded or mirrored *while it is still
///    frontmost*. This never changes `scenePhase`, never resigns active, and so
///    was previously invisible to the app: every live code was captured at full
///    clarity. `ScreenCaptureMonitor` exists to observe it.
///
/// Pure and `nonisolated` so every branch is assertable without a simulator —
/// the same reason `SyncMergeEngine` is pure. The UIKit half that feeds
/// `Conditions` lives in `ScreenCaptureMonitor`.
nonisolated enum PrivacyShield {

    /// What the device is doing right now.
    struct Conditions: Equatable {
        /// `false` while the app is not the frontmost active app.
        var appIsActive: Bool
        /// `true` while the screen is being recorded or mirrored.
        var screenIsCaptured: Bool

        init(appIsActive: Bool = true, screenIsCaptured: Bool = false) {
            self.appIsActive = appIsActive
            self.screenIsCaptured = screenIsCaptured
        }
    }

    /// What the user asked for.
    struct Preferences: Equatable {
        var blurWhenBackgrounded: Bool
        var hideInAppSwitcher: Bool
        var hideWhenScreenCaptured: Bool

        init(blurWhenBackgrounded: Bool = true,
             hideInAppSwitcher: Bool = true,
             hideWhenScreenCaptured: Bool = true) {
            self.blurWhenBackgrounded = blurWhenBackgrounded
            self.hideInAppSwitcher = hideInAppSwitcher
            self.hideWhenScreenCaptured = hideWhenScreenCaptured
        }
    }

    /// Blur the token list.
    ///
    /// This is the softer of the two treatments, and it stays exactly as
    /// permissive as it was before capture monitoring existed: with
    /// `screenIsCaptured == false` it reduces to
    /// `blurWhenBackgrounded && !appIsActive`.
    static func shouldBlur(_ conditions: Conditions, _ preferences: Preferences) -> Bool {
        guard preferences.blurWhenBackgrounded else { return false }
        if !conditions.appIsActive { return true }
        // Still frontmost, but the screen is being captured.
        return conditions.screenIsCaptured && preferences.hideWhenScreenCaptured
    }

    /// Cover the content entirely with the privacy screen.
    ///
    /// The two reasons are OR-ed rather than mutually exclusive. A device can be
    /// recorded while the app sits in the background, and honouring only the
    /// app-switcher setting in that case would let the recording show a
    /// blurred-but-still-present token list.
    ///
    /// With `screenIsCaptured == false` this reduces to
    /// `!appIsActive && hideInAppSwitcher`, which is the previous behaviour.
    static func shouldShowOverlay(_ conditions: Conditions, _ preferences: Preferences) -> Bool {
        let hiddenFromSwitcher = !conditions.appIsActive && preferences.hideInAppSwitcher
        let hiddenFromCapture = conditions.screenIsCaptured && preferences.hideWhenScreenCaptured
        return hiddenFromSwitcher || hiddenFromCapture
    }
}

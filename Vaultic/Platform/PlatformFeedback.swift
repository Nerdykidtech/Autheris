import SwiftUI

#if os(iOS)
import AudioToolbox
import UIKit
#endif

/// The tactile and audible confirmations the app gives on a copy, a reveal, and
/// a save.
///
/// A Mac has no haptic engine, so on macOS every one of these is deliberately a
/// no-op. They are *not* silently dropped behind `#if` at each call site: naming
/// the intent once means an iOS copy still buzzes exactly as it did, and the Mac
/// reads as "this platform has no haptics" rather than "somebody forgot".
enum Haptics {
    enum Impact {
        case light
        case medium

        #if os(iOS)
        var generator: UIImpactFeedbackGenerator {
            switch self {
            case .light: UIImpactFeedbackGenerator(style: .light)
            case .medium: UIImpactFeedbackGenerator(style: .medium)
            }
        }
        #endif
    }

    enum Notification {
        case success
        case warning
        case error

        #if os(iOS)
        var type: UINotificationFeedbackGenerator.FeedbackType {
            switch self {
            case .success: .success
            case .warning: .warning
            case .error: .error
            }
        }
        #endif
    }

    static func impact(_ style: Impact) {
        #if os(iOS)
        style.generator.impactOccurred()
        #endif
    }

    static func notify(_ type: Notification) {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(type.type)
        #endif
    }

    /// The short buzz when the scanner takes a reading. No Mac equivalent.
    static func vibrate() {
        #if os(iOS)
        AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
        #endif
    }
}

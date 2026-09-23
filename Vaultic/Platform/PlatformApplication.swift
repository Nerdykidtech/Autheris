import Foundation

#if os(macOS)
import AppKit
#else
import MessageUI
import UIKit
#endif

/// The small number of questions that are answered by the operating system
/// rather than by the app: what is this machine, where does the user grant camera
/// access, and can anything open a mail draft.
enum PlatformApplication {

    // MARK: - Machine description

    /// The hardware model, as shown in a support email.
    ///
    /// `uname` answers `arm64` on every Apple Silicon Mac, which is useless in a
    /// bug report, so macOS asks the kernel for `hw.model` instead.
    static var deviceModel: String {
        #if os(macOS)
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "Mac" }
        var model = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &model, &size, nil, 0) == 0 else { return "Mac" }
        return String(cString: model)
        #else
        UIDevice.current.model
        #endif
    }

    /// The machine's raw model identifier — `iPhone14,3`, `Mac14,10` — which is
    /// what actually helps when reading a bug report.
    static var machineIdentifier: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        return mirror.children.compactMap { element -> String? in
            guard let value = element.value as? Int8, value != 0 else { return nil }
            return String(UnicodeScalar(UInt8(value)))
        }.joined()
    }

    /// Both halves of the machine's identity, in the shape the support template
    /// has always used.
    static var deviceDescription: String {
        #if os(macOS)
        "Mac (\(deviceModel))"
        #else
        "\(deviceModel) (\(machineIdentifier))"
        #endif
    }

    /// The name of the operating system, so the support template can label its
    /// own version line correctly on each platform.
    static var osName: String {
        #if os(macOS)
        "macOS"
        #else
        UIDevice.current.systemName
        #endif
    }

    /// The marketing version of the operating system, without Apple's build
    /// string: `26.0`, not `Version 26.0 (Build 25A354)`.
    static var osVersion: String {
        #if os(macOS)
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion)"
        #else
        UIDevice.current.systemVersion
        #endif
    }

    // MARK: - Camera permission

    /// Sends the user to the privacy pane where camera access is granted.
    ///
    /// Neither platform lets an app flip its own permission, so both lead to the
    /// system's own switch — which is why this exists at all instead of the app
    /// just re-asking.
    static func openCameraSettings() {
        #if os(macOS)
        // The Mac privacy panes are reached by URL scheme; the anchor names the
        // Camera row so the user lands on the right switch.
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
        #else
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }

    // MARK: - Mail

    /// Whether an in-app mail composer exists on this platform.
    ///
    /// `MFMailComposeViewController` is iOS-only, so the Mac always takes the
    /// `mailto:` route — which on the Mac is not a fallback at all: it opens the
    /// user's real mail client with the draft already filled in, and is the
    /// better behaviour there.
    static var hasInAppMailComposer: Bool {
        #if os(macOS)
        false
        #else
        MFMailComposeViewController.canSendMail()
        #endif
    }

    /// Hands a `mailto:` URL to the platform.
    static func openMail(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }
}

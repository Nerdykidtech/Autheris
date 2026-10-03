import AVFoundation

class CameraPermissionHelper {
    /// `completion` always runs on the main actor, whichever branch answers.
    static func checkCameraPermission(completion: @escaping @MainActor (Bool) -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        
        switch status {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    completion(granted)
                }
            }
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
        }
    }
    
    static func openSettings() {
        PlatformApplication.openCameraSettings()
    }
}

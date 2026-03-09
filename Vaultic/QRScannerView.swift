import SwiftUI
import AVFoundation
import AudioToolbox

struct QRScannerView: UIViewControllerRepresentable {
    @Binding var isScanning: Bool
    let onCodeScanned: (String?) -> Void
    @Environment(\.dismiss) private var dismiss
    
    class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        var parent: QRScannerView
        var captureSession: AVCaptureSession?
        
        init(parent: QRScannerView) {
            self.parent = parent
        }
        
        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard let metadataObject = metadataObjects.first,
                  let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject,
                  let stringValue = readableObject.stringValue else {
                return
            }
            
            // Found a QR code
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            captureSession?.stopRunning()
            
            DispatchQueue.main.async {
                self.parent.onCodeScanned(stringValue)
                self.parent.dismiss()
            }
        }
        
        @objc func handleCancel() {
            DispatchQueue.main.async {
                self.parent.onCodeScanned(nil)
                self.parent.dismiss()
            }
        }
        
        @objc func openSettings() {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
        
        @objc func requestPermission() {
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        self.parent.isScanning = false
                        // Re-open scanner after permission is granted
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self.parent.isScanning = true
                        }
                    } else {
                        self.parent.onCodeScanned(nil)
                        self.parent.dismiss()
                    }
                }
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()
        viewController.view.backgroundColor = .black
        
        // Check camera permission BEFORE setting up the camera
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        
        switch status {
        case .authorized:
            setupCameraSession(viewController: viewController, context: context)
        case .notDetermined:
            // Show permission request UI
            showPermissionRequest(viewController: viewController, context: context)
        case .denied, .restricted:
            // Show permission denied UI
            showPermissionDenied(viewController: viewController, context: context)
        @unknown default:
            showPermissionDenied(viewController: viewController, context: context)
        }
        
        return viewController
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // Update view if needed
    }
    
    private func setupCameraSession(viewController: UIViewController, context: Context) {
        guard let captureDevice = AVCaptureDevice.default(for: .video) else {
            print("No camera device available")
            DispatchQueue.main.async {
                self.onCodeScanned(nil)
                self.dismiss()
            }
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: captureDevice)
            let captureSession = AVCaptureSession()
            
            // Set session preset
            if captureSession.canSetSessionPreset(.hd1280x720) {
                captureSession.sessionPreset = .hd1280x720
            }
            
            // Add input
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            } else {
                print("Could not add input to session")
                DispatchQueue.main.async {
                    self.onCodeScanned(nil)
                    self.dismiss()
                }
                return
            }
            
            // Add metadata output
            let metadataOutput = AVCaptureMetadataOutput()
            if captureSession.canAddOutput(metadataOutput) {
                captureSession.addOutput(metadataOutput)
                
                metadataOutput.setMetadataObjectsDelegate(context.coordinator, queue: DispatchQueue.main)
                metadataOutput.metadataObjectTypes = [.qr]
            } else {
                print("Could not add output to session")
                DispatchQueue.main.async {
                    self.onCodeScanned(nil)
                    self.dismiss()
                }
                return
            }
            
            // Add preview layer
            let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            previewLayer.frame = viewController.view.layer.bounds
            previewLayer.videoGravity = .resizeAspectFill
            viewController.view.layer.addSublayer(previewLayer)
            
            // Add scanning overlay
            addScanningOverlay(to: viewController.view)
            
            // Add cancel button
            addCancelButton(to: viewController, coordinator: context.coordinator)
            
            context.coordinator.captureSession = captureSession
            
            // Start session on main thread
            DispatchQueue.main.async {
                if !captureSession.isRunning {
                    captureSession.startRunning()
                }
            }
            
        } catch {
            print("Failed to setup camera: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.onCodeScanned(nil)
                self.dismiss()
            }
        }
    }
    
    private func showPermissionRequest(viewController: UIViewController, context: Context) {
        // Add instruction label
        let instructionLabel = UILabel()
        instructionLabel.text = "Camera Access Required"
        instructionLabel.textColor = .white
        instructionLabel.font = UIFont.systemFont(ofSize: 24, weight: .bold)
        instructionLabel.textAlignment = .center
        instructionLabel.frame = CGRect(x: 20, y: 100, width: viewController.view.bounds.width - 40, height: 30)
        viewController.view.addSubview(instructionLabel)
        
        let detailLabel = UILabel()
        detailLabel.text = "To scan QR codes, please allow camera access"
        detailLabel.textColor = .white
        detailLabel.font = UIFont.systemFont(ofSize: 16, weight: .regular)
        detailLabel.textAlignment = .center
        detailLabel.numberOfLines = 0
        detailLabel.frame = CGRect(x: 20, y: 150, width: viewController.view.bounds.width - 40, height: 80)
        viewController.view.addSubview(detailLabel)
        
        // Add request permission button
        let requestButton = UIButton(type: .system)
        requestButton.setTitle("Allow Camera Access", for: .normal)
        requestButton.setTitleColor(.white, for: .normal)
        requestButton.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        requestButton.backgroundColor = UIColor.systemBlue
        requestButton.layer.cornerRadius = 12
        requestButton.contentEdgeInsets = UIEdgeInsets(top: 12, left: 24, bottom: 12, right: 24)
        
        requestButton.addTarget(context.coordinator, action: #selector(Coordinator.requestPermission), for: .touchUpInside)
        
        requestButton.translatesAutoresizingMaskIntoConstraints = false
        viewController.view.addSubview(requestButton)
        
        NSLayoutConstraint.activate([
            requestButton.centerXAnchor.constraint(equalTo: viewController.view.centerXAnchor),
            requestButton.centerYAnchor.constraint(equalTo: viewController.view.centerYAnchor),
            requestButton.widthAnchor.constraint(equalToConstant: 250)
        ])
        
        // Add cancel button
        addCancelButton(to: viewController, coordinator: context.coordinator)
    }
    
    private func showPermissionDenied(viewController: UIViewController, context: Context) {
        // Add instruction label
        let instructionLabel = UILabel()
        instructionLabel.text = "Camera Access Denied"
        instructionLabel.textColor = .white
        instructionLabel.font = UIFont.systemFont(ofSize: 24, weight: .bold)
        instructionLabel.textAlignment = .center
        instructionLabel.frame = CGRect(x: 20, y: 100, width: viewController.view.bounds.width - 40, height: 30)
        viewController.view.addSubview(instructionLabel)
        
        let detailLabel = UILabel()
        detailLabel.text = "Camera access is required to scan QR codes. Please enable it in Settings."
        detailLabel.textColor = .white
        detailLabel.font = UIFont.systemFont(ofSize: 16, weight: .regular)
        detailLabel.textAlignment = .center
        detailLabel.numberOfLines = 0
        detailLabel.frame = CGRect(x: 20, y: 150, width: viewController.view.bounds.width - 40, height: 80)
        viewController.view.addSubview(detailLabel)
        
        // Add open settings button
        let settingsButton = UIButton(type: .system)
        settingsButton.setTitle("Open Settings", for: .normal)
        settingsButton.setTitleColor(.white, for: .normal)
        settingsButton.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        settingsButton.backgroundColor = UIColor.systemBlue
        settingsButton.layer.cornerRadius = 12
        settingsButton.contentEdgeInsets = UIEdgeInsets(top: 12, left: 24, bottom: 12, right: 24)
        
        settingsButton.addTarget(context.coordinator, action: #selector(Coordinator.openSettings), for: .touchUpInside)
        
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        viewController.view.addSubview(settingsButton)
        
        NSLayoutConstraint.activate([
            settingsButton.centerXAnchor.constraint(equalTo: viewController.view.centerXAnchor),
            settingsButton.centerYAnchor.constraint(equalTo: viewController.view.centerYAnchor),
            settingsButton.widthAnchor.constraint(equalToConstant: 200)
        ])
        
        // Add cancel button
        addCancelButton(to: viewController, coordinator: context.coordinator)
    }
    
    private func addCancelButton(to viewController: UIViewController, coordinator: Coordinator) {
        let cancelButton = UIButton(type: .system)
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.setTitleColor(.white, for: .normal)
        cancelButton.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        cancelButton.backgroundColor = UIColor.systemGray.withAlphaComponent(0.3)
        cancelButton.layer.cornerRadius = 12
        cancelButton.contentEdgeInsets = UIEdgeInsets(top: 12, left: 24, bottom: 12, right: 24)
        
        cancelButton.addTarget(coordinator, action: #selector(Coordinator.handleCancel), for: .touchUpInside)
        
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        viewController.view.addSubview(cancelButton)
        
        NSLayoutConstraint.activate([
            cancelButton.centerXAnchor.constraint(equalTo: viewController.view.centerXAnchor),
            cancelButton.bottomAnchor.constraint(equalTo: viewController.view.safeAreaLayoutGuide.bottomAnchor, constant: -30)
        ])
    }
    
    private func addScanningOverlay(to view: UIView) {
        // Dimmed background
        let dimmedView = UIView(frame: view.bounds)
        dimmedView.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        
        // Create transparent scanning window
        let path = UIBezierPath(rect: view.bounds)
        let scanningRect = CGRect(x: (view.bounds.width - 250) / 2,
                                 y: (view.bounds.height - 250) / 2,
                                 width: 250,
                                 height: 250)
        let scanningPath = UIBezierPath(roundedRect: scanningRect, cornerRadius: 20)
        path.append(scanningPath.reversing())
        
        let maskLayer = CAShapeLayer()
        maskLayer.path = path.cgPath
        dimmedView.layer.mask = maskLayer
        
        // Add border to scanning window
        let borderLayer = CAShapeLayer()
        borderLayer.path = scanningPath.cgPath
        borderLayer.strokeColor = UIColor.white.cgColor
        borderLayer.lineWidth = 3
        borderLayer.fillColor = UIColor.clear.cgColor
        dimmedView.layer.addSublayer(borderLayer)
        
        // Add corner markers
        addCornerMarkers(to: dimmedView, scanningRect: scanningRect)
        
        // Add instruction label
        let instructionLabel = UILabel()
        instructionLabel.text = "Position QR code within frame"
        instructionLabel.textColor = .white
        instructionLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        instructionLabel.textAlignment = .center
        instructionLabel.frame = CGRect(x: 0,
                                       y: scanningRect.maxY + 20,
                                       width: view.bounds.width,
                                       height: 24)
        dimmedView.addSubview(instructionLabel)
        
        view.addSubview(dimmedView)
    }
    
    private func addCornerMarkers(to view: UIView, scanningRect: CGRect) {
        let cornerLength: CGFloat = 30
        let cornerWidth: CGFloat = 4
        
        // Top left corner
        addCornerLine(to: view,
                     start: CGPoint(x: scanningRect.minX, y: scanningRect.minY + cornerLength),
                     end: CGPoint(x: scanningRect.minX, y: scanningRect.minY))
        addCornerLine(to: view,
                     start: CGPoint(x: scanningRect.minX, y: scanningRect.minY),
                     end: CGPoint(x: scanningRect.minX + cornerLength, y: scanningRect.minY))
        
        // Top right corner
        addCornerLine(to: view,
                     start: CGPoint(x: scanningRect.maxX - cornerLength, y: scanningRect.minY),
                     end: CGPoint(x: scanningRect.maxX, y: scanningRect.minY))
        addCornerLine(to: view,
                     start: CGPoint(x: scanningRect.maxX, y: scanningRect.minY),
                     end: CGPoint(x: scanningRect.maxX, y: scanningRect.minY + cornerLength))
        
        // Bottom left corner
        addCornerLine(to: view,
                     start: CGPoint(x: scanningRect.minX, y: scanningRect.maxY - cornerLength),
                     end: CGPoint(x: scanningRect.minX, y: scanningRect.maxY))
        addCornerLine(to: view,
                     start: CGPoint(x: scanningRect.minX, y: scanningRect.maxY),
                     end: CGPoint(x: scanningRect.minX + cornerLength, y: scanningRect.maxY))
        
        // Bottom right corner
        addCornerLine(to: view,
                     start: CGPoint(x: scanningRect.maxX - cornerLength, y: scanningRect.maxY),
                     end: CGPoint(x: scanningRect.maxX, y: scanningRect.maxY))
        addCornerLine(to: view,
                     start: CGPoint(x: scanningRect.maxX, y: scanningRect.maxY),
                     end: CGPoint(x: scanningRect.maxX, y: scanningRect.maxY - cornerLength))
    }
    
    private func addCornerLine(to view: UIView, start: CGPoint, end: CGPoint) {
        let path = UIBezierPath()
        path.move(to: start)
        path.addLine(to: end)
        
        let shapeLayer = CAShapeLayer()
        shapeLayer.path = path.cgPath
        shapeLayer.strokeColor = UIColor.systemBlue.cgColor
        shapeLayer.lineWidth = 4
        shapeLayer.lineCap = .round
        
        view.layer.addSublayer(shapeLayer)
    }
}


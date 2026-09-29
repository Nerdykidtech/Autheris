import SwiftUI
// `AVCaptureSession` is documented as safe to start and stop from another thread
// but is not annotated `Sendable`, so the explicit annotation is what keeps that
// deliberate cross-thread use from being reported as a hazard.
@preconcurrency import AVFoundation

#if os(iOS)

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
            Haptics.vibrate()
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
            PlatformApplication.openCameraSettings()
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
            #if DEBUG
            print("No camera device available")
            #endif
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
                #if DEBUG
                print("Could not add input to session")
                #endif
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
                #if DEBUG
                print("Could not add output to session")
                #endif
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
            
            // startRunning is blocking; keep it off the main thread so the UI stays responsive.
            DispatchQueue.global(qos: .userInitiated).async {
                if !captureSession.isRunning {
                    captureSession.startRunning()
                }
            }
            
        } catch {
            #if DEBUG
            print("Failed to setup camera: \(error.localizedDescription)")
            #endif
            DispatchQueue.main.async {
                self.onCodeScanned(nil)
                self.dismiss()
            }
        }
    }
    
    private func showPermissionRequest(viewController: UIViewController, context: Context) {
        // Add instruction label
        let instructionLabel = UILabel()
        instructionLabel.text = String(localized: "Camera Access Required")
        instructionLabel.textColor = .white
        instructionLabel.font = UIFont.systemFont(ofSize: 24, weight: .bold)
        instructionLabel.textAlignment = .center
        instructionLabel.frame = CGRect(x: 20, y: 100, width: viewController.view.bounds.width - 40, height: 30)
        viewController.view.addSubview(instructionLabel)
        
        let detailLabel = UILabel()
        detailLabel.text = String(localized: "To scan QR codes, please allow camera access")
        detailLabel.textColor = .white
        detailLabel.font = UIFont.systemFont(ofSize: 16, weight: .regular)
        detailLabel.textAlignment = .center
        detailLabel.numberOfLines = 0
        detailLabel.frame = CGRect(x: 20, y: 150, width: viewController.view.bounds.width - 40, height: 80)
        viewController.view.addSubview(detailLabel)
        
        var requestConfig = UIButton.Configuration.filled()
        requestConfig.title = String(localized: "Allow Camera Access")
        requestConfig.baseForegroundColor = .white
        requestConfig.baseBackgroundColor = .systemBlue
        requestConfig.background.cornerRadius = 12
        requestConfig.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 24)
        requestConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var out = incoming
            out.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
            return out
        }
        let requestButton = UIButton(configuration: requestConfig)
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
        instructionLabel.text = String(localized: "Camera Access Denied")
        instructionLabel.textColor = .white
        instructionLabel.font = UIFont.systemFont(ofSize: 24, weight: .bold)
        instructionLabel.textAlignment = .center
        instructionLabel.frame = CGRect(x: 20, y: 100, width: viewController.view.bounds.width - 40, height: 30)
        viewController.view.addSubview(instructionLabel)
        
        let detailLabel = UILabel()
        detailLabel.text = String(localized: "Camera access is required to scan QR codes. Please enable it in Settings.")
        detailLabel.textColor = .white
        detailLabel.font = UIFont.systemFont(ofSize: 16, weight: .regular)
        detailLabel.textAlignment = .center
        detailLabel.numberOfLines = 0
        detailLabel.frame = CGRect(x: 20, y: 150, width: viewController.view.bounds.width - 40, height: 80)
        viewController.view.addSubview(detailLabel)
        
        var settingsConfig = UIButton.Configuration.filled()
        settingsConfig.title = String(localized: "Open Settings")
        settingsConfig.baseForegroundColor = .white
        settingsConfig.baseBackgroundColor = .systemBlue
        settingsConfig.background.cornerRadius = 12
        settingsConfig.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 24)
        settingsConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var out = incoming
            out.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
            return out
        }
        let settingsButton = UIButton(configuration: settingsConfig)
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
        var cancelConfig = UIButton.Configuration.filled()
        cancelConfig.title = String(localized: "Cancel")
        cancelConfig.baseForegroundColor = .white
        cancelConfig.baseBackgroundColor = UIColor.systemGray.withAlphaComponent(0.3)
        cancelConfig.background.cornerRadius = 12
        cancelConfig.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 24)
        cancelConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var out = incoming
            out.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
            return out
        }
        let cancelButton = UIButton(configuration: cancelConfig)
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
        instructionLabel.text = String(localized: "Position QR code within frame")
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

#else

import AppKit

/// The Mac's QR scanner.
///
/// iOS needs a hand-built `UIViewController` because the preview layer has to be
/// hosted in a `UIView` and there is nowhere else for the labels and buttons to
/// live. AppKit hosts the preview just as easily, so the Mac draws the frame, its
/// corner brackets and every permission state in SwiftUI instead — a good deal
/// less code, and consistent with the rest of the app.
///
/// The capture session itself is plain AVFoundation and identical on both
/// platforms; only the presentation differs.
struct QRScannerView: View {
    @Binding var isScanning: Bool
    let onCodeScanned: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var authorization = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var scanner: ScannerSession?
    /// macOS will not hand a freshly-granted camera to the process that asked for
    /// it — the permission only takes effect on the next launch. So the session
    /// can fail to build even with `.authorized` showing, and that is worth
    /// saying out loud rather than leaving the user on a spinner.
    @State private var needsRelaunch = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch authorization {
            case .authorized:
                if let scanner {
                    CameraPreview(session: scanner.session)
                        .ignoresSafeArea()
                        // The frame and its corner brackets are drawn across the whole
                        // surface, so they must not intercept the way out layered on
                        // top of them below.
                        .overlay(scanningOverlay.allowsHitTesting(false))
                        .overlay(alignment: .bottom) { closeButton }
                } else if needsRelaunch {
                    relaunchNotice
                } else {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(alignment: .bottom) { closeButton }
                }

            case .notDetermined:
                permissionRequest

            default:
                permissionDenied
            }
        }
        .frame(minWidth: 480, minHeight: 480)
        .onAppear(perform: start)
        .onDisappear { scanner?.stop() }
    }

    // MARK: - Dismissal

    /// The way out of the scanner.
    ///
    /// The iPhone build gets this from a `UIButton` added to its hand-built view
    /// controller. Each Mac state carries its own action button — permission
    /// request, permission denied, and relaunch all have one — but the live
    /// preview and the brief loading state had none, which left a sheet that
    /// macOS will not dismiss by clicking outside it. It is layered *over* the
    /// scanning frame rather than under it for the same reason.
    private var closeButton: some View {
        Button {
            finish(with: nil)
        } label: {
            Text("Cancel")
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 22)
                .padding(.vertical, 10)
                .background(Capsule().fill(.black.opacity(0.55)))
                .foregroundStyle(.white)
        }
        .platformPlainButton()
        // Escape works too, which is the first thing a Mac user reaches for.
        .keyboardShortcut(.cancelAction)
        .padding(.bottom, 28)
    }

    // MARK: - Overlay

    /// The scanning frame: everything outside it dimmed, a bright bracket at each
    /// corner, and the same instruction the iPhone shows.
    private var scanningOverlay: some View {
        GeometryReader { geometry in
            let side: CGFloat = 250
            let frame = CGRect(
                x: (geometry.size.width - side) / 2,
                y: (geometry.size.height - side) / 2,
                width: side,
                height: side
            )

            ZStack {
                Canvas { context, size in
                    // Everything but the scanning frame, as one even-odd fill.
                    var dimmed = Path(CGRect(origin: .zero, size: size))
                    dimmed.addPath(Path(roundedRect: frame, cornerRadius: 20))
                    context.fill(
                        dimmed,
                        with: .color(.black.opacity(0.7)),
                        style: FillStyle(eoFill: true)
                    )

                    context.stroke(
                        Path(roundedRect: frame, cornerRadius: 20),
                        with: .color(.white),
                        lineWidth: 3
                    )

                    let cornerLength: CGFloat = 30
                    let brackets = Path { path in
                        // Top left
                        path.move(to: CGPoint(x: frame.minX, y: frame.minY + cornerLength))
                        path.addLine(to: CGPoint(x: frame.minX, y: frame.minY))
                        path.addLine(to: CGPoint(x: frame.minX + cornerLength, y: frame.minY))
                        // Top right
                        path.move(to: CGPoint(x: frame.maxX - cornerLength, y: frame.minY))
                        path.addLine(to: CGPoint(x: frame.maxX, y: frame.minY))
                        path.addLine(to: CGPoint(x: frame.maxX, y: frame.minY + cornerLength))
                        // Bottom left
                        path.move(to: CGPoint(x: frame.minX, y: frame.maxY - cornerLength))
                        path.addLine(to: CGPoint(x: frame.minX, y: frame.maxY))
                        path.addLine(to: CGPoint(x: frame.minX + cornerLength, y: frame.maxY))
                        // Bottom right
                        path.move(to: CGPoint(x: frame.maxX - cornerLength, y: frame.maxY))
                        path.addLine(to: CGPoint(x: frame.maxX, y: frame.maxY))
                        path.addLine(to: CGPoint(x: frame.maxX, y: frame.maxY - cornerLength))
                    }
                    context.stroke(
                        brackets,
                        with: .color(.blue),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                }

                Text("Position QR code within frame")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white)
                    .position(x: geometry.size.width / 2, y: frame.maxY + 32)
            }
        }
    }

    // MARK: - Permission states

    private var permissionRequest: some View {
        VStack(spacing: 20) {
            Text("Camera Access Required")
                .font(.title.weight(.bold))
            Text("To scan QR codes, please allow camera access")
                .foregroundStyle(.white.opacity(0.8))

            Button("Allow Camera Access") {
                requestPermission()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button("Cancel") { finish(with: nil) }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.7))
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .padding(40)
    }

    private var permissionDenied: some View {
        VStack(spacing: 20) {
            Text("Camera Access Denied")
                .font(.title.weight(.bold))
            Text("Camera access is required to scan QR codes. Please enable it in System Settings under Privacy & Security → Camera.")
                .foregroundStyle(.white.opacity(0.8))
                .frame(maxWidth: 360)

            Button("Open System Settings") {
                PlatformApplication.openCameraSettings()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button("Cancel") { finish(with: nil) }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.7))
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .padding(40)
    }

    private var relaunchNotice: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.8))
            Text("Camera Access Granted")
                .font(.title2.weight(.bold))
            Text("macOS applies camera access the next time an app starts. Quit and reopen Autheris to use the scanner — or add the code from a picture instead.")
                .foregroundStyle(.white.opacity(0.8))
                .frame(maxWidth: 360)
            Button("Done") { finish(with: nil) }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .padding(40)
    }

    // MARK: - Session

    private func start() {
        guard authorization == .authorized, scanner == nil else { return }
        if let scanner = ScannerSession(onCode: { value in finish(with: value) }) {
            self.scanner = scanner
            scanner.start()
        } else {
            #if DEBUG
            print("No camera device available")
            #endif
            needsRelaunch = true
        }
    }

    private func requestPermission() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                authorization = granted ? .authorized : .denied
                if granted { start() } else { finish(with: nil) }
            }
        }
    }

    private func finish(with value: String?) {
        scanner?.stop()
        onCodeScanned(value)
        dismiss()
    }
}

/// The capture session and its delegate, which are plain AVFoundation and so
/// identical to what the iOS path uses.
@MainActor
private final class ScannerSession: NSObject, AVCaptureMetadataOutputObjectsDelegate {
    let session = AVCaptureSession()
    private let output = AVCaptureMetadataOutput()
    private let onCode: (String) -> Void

    init?(onCode: @escaping (String) -> Void) {
        self.onCode = onCode
        super.init()

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return nil }

        session.beginConfiguration()
        if session.canSetSessionPreset(.hd1280x720) {
            session.sessionPreset = .hd1280x720
        }
        let configured = session.canAddInput(input) && session.canAddOutput(output)
        if configured {
            session.addInput(input)
            session.addOutput(output)
        }
        session.commitConfiguration()
        guard configured else { return nil }

        // The delegate queue is the main queue, which is what lets the callback
        // below assume main-actor isolation.
        output.setMetadataObjectsDelegate(self, queue: .main)

        // QR detection is switched on *after* the configuration is committed, and
        // only once the output says it offers `.qr`. See
        // `enableQRDetectionIfAvailable` for why that ordering is load-bearing.
        enableQRDetectionIfAvailable()

        // On macOS the available set is only reliably published once the session is
        // actually running, so this is the second attempt.
        NotificationCenter.default.addObserver(
            forName: AVCaptureSession.didStartRunningNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            // `queue: .main` means this really is running on the main actor, which
            // the compiler cannot see through the callback signature.
            MainActor.assumeIsolated {
                _ = self?.enableQRDetectionIfAvailable()
            }
        }
    }

    /// Turns on QR detection, if the output offers it.
    ///
    /// `metadataObjectTypes` may only be assigned a subset of
    /// `availableMetadataObjectTypes`, and assigning anything else **raises**
    /// `NSInvalidArgumentException`. Swift cannot catch that, so it becomes a
    /// SIGTRAP and takes the app down with it — which is exactly what happened the
    /// moment Scan was pressed.
    ///
    /// Two things were wrong. The assignment sat inside the
    /// `beginConfiguration()` block, where the available set has not yet been
    /// derived from the input being added, so `.qr` looked unsupported and
    /// AVFoundation raised. And on macOS the set is only dependable once the
    /// session is running, which is why this is also called from
    /// `didStartRunningNotification` and from `start()`.
    ///
    /// Guarding on the available set means this can never raise, whatever the
    /// session does.
    ///
    /// Returns `true` when QR detection is live.
    @discardableResult
    private func enableQRDetectionIfAvailable() -> Bool {
        guard !output.metadataObjectTypes.contains(.qr) else { return true }
        guard output.availableMetadataObjectTypes.contains(.qr) else {
            #if DEBUG
            print("Camera is not offering QR detection yet. Available: \(output.availableMetadataObjectTypes)")
            #endif
            return false
        }
        output.metadataObjectTypes = [.qr]
        return true
    }

    func start() {
        guard !session.isRunning else { return }
        // A second scan in the same launch finds the session already running, and
        // then `didStartRunningNotification` will not fire again.
        enableQRDetectionIfAvailable()
        // startRunning blocks; keep it off the main thread so the window stays
        // responsive.
        let session = self.session
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    func stop() {
        guard session.isRunning else { return }
        let session = self.session
        DispatchQueue.global(qos: .userInitiated).async {
            session.stopRunning()
        }
    }

    nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput,
                                    didOutput metadataObjects: [AVMetadataObject],
                                    from connection: AVCaptureConnection) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue else { return }

        MainActor.assumeIsolated {
            stop()
            onCode(value)
        }
    }
}

/// Hosts an `AVCaptureVideoPreviewLayer` in an AppKit view.
private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.wantsLayer = true

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        // The preview layer is a layer, not a view, so AppKit will not lay it
        // out; it tracks its host through layer autoresizing instead.
        preview.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer?.addSublayer(preview)

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView.layer?.sublayers?.first as? AVCaptureVideoPreviewLayer)?.session = session
    }
}
#endif

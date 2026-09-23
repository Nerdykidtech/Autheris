import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

struct QRCodeView: View {
    let data: Data
    let title: String
    
    @Environment(\.dismiss) private var dismiss
    @State private var qrImage: PlatformImage?
    @State private var generationError: String?
    @State private var isSharing = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                if let generationError {
                    VStack(spacing: 16) {
                        Image(systemName: "qrcode")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                            .symbolRenderingMode(.hierarchical)
                        Text("Couldn’t create QR code")
                            .font(.headline)
                        Text(generationError)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                } else if let qrImage {
                    Image(platformImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 250, height: 250)
                        .padding(20)
                        .background(Color.white)
                        .cornerRadius(12)
                        .shadow(radius: 8)
                    
                    Text("Scan this QR code with another device to import all tokens")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    
                    Text("Tip: You can also scan this with your iPhone camera")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .padding(.top, 8)
                } else {
                    ProgressView("Generating QR Code...")
                        .frame(width: 250, height: 250)
                }
                
                Spacer()
                
                Button(action: {
                    shareQRCode()
                }) {
                    Label("Share QR Code", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(
                            Capsule()
                                .fill(Color.accentColor)
                        )
                        .foregroundColor(.white)
                }
                .disabled(qrImage == nil)
                .opacity(qrImage == nil ? 0.45 : 1)
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
            .padding(.top, 40)
            .navigationTitle(title)
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .platformSheetTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                generateQRCode()
            }
            .sheet(isPresented: $isSharing) {
                if let qrImage {
                    PlatformShareSheet(activityItems: [qrImage])
                }
            }
        }
        .platformSheetSize(minHeight: 560)
    }
    
    private func generateQRCode() {
        let payloadData = data
        DispatchQueue.global(qos: .userInitiated).async {
            let context = CIContext()
            let filter = CIFilter.qrCodeGenerator()
            filter.setValue("L", forKey: "inputCorrectionLevel")
            
            let base64String = payloadData.base64EncodedString()
            let encodedBase64String = base64String
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
            
            let urlString = "autheris://import?data=\(encodedBase64String)"
            
            let messageData: Data?
            if let qrData = urlString.data(using: .utf8) {
                messageData = qrData
            } else {
                messageData = payloadData
            }
            
            guard let messageData else {
                DispatchQueue.main.async {
                    generationError = "The export data could not be encoded for a QR code."
                }
                return
            }
            
            filter.message = messageData
            
            guard let outputImage = filter.outputImage else {
                DispatchQueue.main.async {
                    generationError = "This export is too large for a single QR code. Use Backup from the menu to transfer your tokens as a file instead."
                }
                return
            }
            
            let transformedImage = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
            
            guard let cgImage = context.createCGImage(transformedImage, from: transformedImage.extent) else {
                DispatchQueue.main.async {
                    generationError = "Could not render the QR image. Try again, or use Backup to export your tokens."
                }
                return
            }
            
            let image = PlatformImage.from(cgImage: cgImage)
            DispatchQueue.main.async {
                qrImage = image
            }
        }
    }
    
    private func shareQRCode() {
        isSharing = true
    }
}

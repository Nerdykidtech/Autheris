import SwiftUI
import CoreImage.CIFilterBuiltins

struct QRCodeView: View {
    let data: Data
    let title: String
    
    @Environment(\.dismiss) private var dismiss
    @State private var qrImage: UIImage?
    @State private var isSharing = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                if let qrImage = qrImage {
                    Image(uiImage: qrImage)
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
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
            .padding(.top, 40)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                generateQRCode()
            }
            .sheet(isPresented: $isSharing) {
                if let qrImage = qrImage {
                    ActivityViewController(activityItems: [qrImage])
                }
            }
        }
    }
    
    private func generateQRCode() {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        
        // Encode as Base64 string for better QR code compatibility
        let base64String = data.base64EncodedString()
        
        // Create a URL with our custom scheme
        // Base64 strings can contain '+' and '/' which need to be URL-encoded
        let encodedBase64String = base64String
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        
        let urlString = "autheris://import?data=\(encodedBase64String)"
        
        // Convert to Data for QR code
        if let qrData = urlString.data(using: .utf8) {
            filter.message = qrData
        } else {
            filter.message = data
        }
        
        if let outputImage = filter.outputImage {
            let transformedImage = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
            
            if let cgImage = context.createCGImage(transformedImage, from: transformedImage.extent) {
                qrImage = UIImage(cgImage: cgImage)
            }
        }
    }
    
    private func shareQRCode() {
        isSharing = true
    }
}

struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

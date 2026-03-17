import UIKit

func generateAppIcons() {
    let sizes: [CGFloat] = [20, 29, 40, 60, 76, 83.5, 1024]
    let scales: [CGFloat] = [1, 2, 3]
    
    for size in sizes {
        for scale in scales {
            let pixelSize = size * scale
            if pixelSize > 0 {
                let iconSize = CGSize(width: pixelSize, height: pixelSize)
                if let icon = AppIconGenerator.generateSimpleShieldIcon(size: iconSize, color: .systemBlue) {
                    // Save the image to a file
                    if let data = icon.pngData() {
                        let filename = "AppIcon-\(Int(size))x\(Int(size))@\(Int(scale))x.png"
                        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(filename)
                        try? data.write(to: url)
                        #if DEBUG
                        print("Generated: \(filename)")
                        #endif
                    }
                }
            }
        }
    }
}

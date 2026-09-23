// iOS-only: unreferenced icon-generation scratch code. Excluded from the
// macOS build rather than ported, because nothing calls it.
#if os(iOS)
import UIKit
import CoreGraphics

struct AppIconGenerator {
    
    static func generateSimpleLockIcon(size: CGSize, color: UIColor = .systemBlue) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: size)
        
        return renderer.image { context in
            // Draw background circle
            let circleRect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
            let circlePath = UIBezierPath(ovalIn: circleRect)
            color.setFill()
            circlePath.fill()
            
            // Draw lock body (white)
            let lockWidth = size.width * 0.6
            let lockHeight = size.height * 0.5
            let lockX = (size.width - lockWidth) / 2
            let lockY = (size.height - lockHeight) / 2 + size.height * 0.1
            
            UIColor.white.setFill()
            let lockBody = UIBezierPath(roundedRect: CGRect(x: lockX, y: lockY, width: lockWidth, height: lockHeight), cornerRadius: 8)
            lockBody.fill()
            
            // Draw lock shackle
            let shackleWidth = lockWidth * 0.8
            let shackleHeight = size.height * 0.25
            let shackleX = (size.width - shackleWidth) / 2
            let shackleY = lockY - shackleHeight * 0.7
            
            UIColor.white.setStroke()
            UIColor.white.setFill()
            
            let shacklePath = UIBezierPath()
            shacklePath.lineWidth = size.width * 0.08
            shacklePath.move(to: CGPoint(x: shackleX, y: shackleY + shackleHeight))
            shacklePath.addQuadCurve(to: CGPoint(x: shackleX + shackleWidth, y: shackleY + shackleHeight),
                                    controlPoint: CGPoint(x: shackleX + shackleWidth/2, y: shackleY))
            shacklePath.addLine(to: CGPoint(x: shackleX + shackleWidth, y: lockY))
            shacklePath.stroke()
        }
    }
    
    static func generateSimpleShieldIcon(size: CGSize, color: UIColor = .systemBlue) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: size)
        
        return renderer.image { context in
            // Draw background circle
            let circleRect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
            let circlePath = UIBezierPath(ovalIn: circleRect)
            color.setFill()
            circlePath.fill()
            
            // Draw shield (white)
            UIColor.white.setFill()
            
            let shieldWidth = size.width * 0.7
            let shieldHeight = size.height * 0.7
            let shieldX = (size.width - shieldWidth) / 2
            let shieldY = (size.height - shieldHeight) / 2
            
            let shieldPath = UIBezierPath()
            shieldPath.move(to: CGPoint(x: shieldX + shieldWidth/2, y: shieldY))
            shieldPath.addLine(to: CGPoint(x: shieldX + shieldWidth, y: shieldY + shieldHeight/3))
            shieldPath.addLine(to: CGPoint(x: shieldX + shieldWidth, y: shieldY + shieldHeight))
            shieldPath.addLine(to: CGPoint(x: shieldX, y: shieldY + shieldHeight))
            shieldPath.addLine(to: CGPoint(x: shieldX, y: shieldY + shieldHeight/3))
            shieldPath.close()
            shieldPath.fill()
            
            // Draw checkmark inside shield
            let checkWidth = shieldWidth * 0.5
            let checkHeight = shieldHeight * 0.5
            let checkX = shieldX + (shieldWidth - checkWidth) / 2
            let checkY = shieldY + (shieldHeight - checkHeight) / 2
            
            color.setStroke()
            let checkPath = UIBezierPath()
            checkPath.lineWidth = size.width * 0.05
            checkPath.lineCapStyle = .round
            checkPath.lineJoinStyle = .round
            
            checkPath.move(to: CGPoint(x: checkX, y: checkY + checkHeight/2))
            checkPath.addLine(to: CGPoint(x: checkX + checkWidth/3, y: checkY + checkHeight))
            checkPath.addLine(to: CGPoint(x: checkX + checkWidth, y: checkY))
            checkPath.stroke()
        }
    }
}
#endif

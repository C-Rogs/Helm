import Foundation
import SwiftUI

/// Shared 270-degree Helm arc: gap at the bottom, sweep through the top.
public enum HelmArcGeometry {
    public static let sweepFraction: Double = 0.75
    public static let rotationDegrees: Double = 135
    public static let sweepDegrees: Double = 270

    public static func defaultStrokeWidth(radius: CGFloat) -> CGFloat {
        min(radius * 0.12, 14)
    }

    public static func calorieStrokeWidth(radius: CGFloat) -> CGFloat {
        min(radius * 0.13, 16)
    }

    public static func angle(fraction: Double) -> Angle {
        Angle.degrees(rotationDegrees + fraction * sweepDegrees)
    }

    public static func point(fraction: Double, center: CGPoint, radius: CGFloat) -> CGPoint {
        let radians = Double(angle(fraction: fraction).radians)
        return CGPoint(
            x: center.x + CGFloat(cos(radians)) * radius,
            y: center.y + CGFloat(sin(radians)) * radius
        )
    }
}

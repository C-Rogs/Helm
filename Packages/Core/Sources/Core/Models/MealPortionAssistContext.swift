import Foundation

/// Depth-derived portion hints from LiDAR capture (camera-only).
public struct MealPortionAssistContext: Sendable, Equatable {
    public let gramScaleFactor: Double
    public let medianDepthMeters: Double
    public let referenceDepthMeters: Double
    /// Width of the center depth patch. Nil when the camera has no calibration.
    public let centerSpanCentimeters: Double?

    public init(
        gramScaleFactor: Double,
        medianDepthMeters: Double,
        referenceDepthMeters: Double,
        centerSpanCentimeters: Double? = nil
    ) {
        self.gramScaleFactor = gramScaleFactor
        self.medianDepthMeters = medianDepthMeters
        self.referenceDepthMeters = referenceDepthMeters
        self.centerSpanCentimeters = centerSpanCentimeters
    }

    /// Short line for the camera and confirm sheet. Distance only when span is unknown.
    public var measurementLine: String {
        let depthCm = Int((medianDepthMeters * 100).rounded())
        guard let centerSpanCentimeters else {
            return "\(depthCm) cm away"
        }
        let spanCm = Int(centerSpanCentimeters.rounded())
        return "\(depthCm) cm away · \(spanCm) cm across"
    }

    /// Prompt context appended to meal vision user notes.
    public var visionPromptContext: String {
        let depthCm = Int((medianDepthMeters * 100).rounded())
        let refCm = Int((referenceDepthMeters * 100).rounded())
        let pct = Int(((gramScaleFactor - 1) * 100).rounded())
        let direction = pct >= 0 ? "larger" : "smaller"
        var text = "LiDAR depth assist: food surface ~\(depthCm)cm from camera (reference \(refCm)cm)."
        if let centerSpanCentimeters {
            let spanCm = Int(centerSpanCentimeters.rounded())
            text += " Center patch is about \(spanCm)cm across."
        }
        text += " Scale portion grams ~\(abs(pct))% \(direction) than an RGB-only estimate."
        return text
    }
}

/// Pixel-to-centimetre width of the center depth patch. No camera types, so tests can run without a device.
public enum MealDepthSpan {
    public static let centerROIFraction = 0.4

    public static func centerSpanCentimeters(
        depthMapWidthPixels: Double,
        roiFraction: Double = centerROIFraction,
        focalLengthPixels: Double,
        intrinsicReferenceWidthPixels: Double,
        depthMeters: Double
    ) -> Double? {
        guard depthMapWidthPixels > 0,
              roiFraction > 0, roiFraction <= 1,
              focalLengthPixels > 0,
              intrinsicReferenceWidthPixels > 0,
              depthMeters > 0 else {
            return nil
        }
        let roiPixels = depthMapWidthPixels * roiFraction
        let focalLengthInDepthPixels = focalLengthPixels * (depthMapWidthPixels / intrinsicReferenceWidthPixels)
        guard focalLengthInDepthPixels > 0 else { return nil }
        return (roiPixels / focalLengthInDepthPixels) * depthMeters * 100
    }
}

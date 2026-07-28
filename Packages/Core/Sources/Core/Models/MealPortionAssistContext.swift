import Foundation

/// Depth-derived portion hints from LiDAR capture (camera-only).
public struct MealPortionAssistContext: Sendable, Equatable {
    public let gramScaleFactor: Double
    public let medianDepthMeters: Double
    public let referenceDepthMeters: Double

    public init(
        gramScaleFactor: Double,
        medianDepthMeters: Double,
        referenceDepthMeters: Double
    ) {
        self.gramScaleFactor = gramScaleFactor
        self.medianDepthMeters = medianDepthMeters
        self.referenceDepthMeters = referenceDepthMeters
    }

    /// Prompt context appended to meal vision user notes.
    public var visionPromptContext: String {
        let depthCm = Int((medianDepthMeters * 100).rounded())
        let refCm = Int((referenceDepthMeters * 100).rounded())
        let pct = Int(((gramScaleFactor - 1) * 100).rounded())
        let direction = pct >= 0 ? "larger" : "smaller"
        return "LiDAR depth assist: food surface ~\(depthCm)cm from camera (reference \(refCm)cm). Scale portion grams ~\(abs(pct))% \(direction) than an RGB-only estimate."
    }
}

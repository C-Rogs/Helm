import Foundation

/// Progress fraction for the rest banner track (remaining empties as time elapses).
public enum RestTimerBannerProgress {
    /// 1 = full remaining; 0 = empty. Clamped to 0...1.
    public static func remainingFraction(remainingSeconds: Int, totalSeconds: Int) -> Double {
        let total = max(1, totalSeconds)
        let remaining = min(total, max(0, remainingSeconds))
        return Double(remaining) / Double(total)
    }
}

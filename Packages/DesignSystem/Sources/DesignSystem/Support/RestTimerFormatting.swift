import Foundation

/// Shared mm:ss formatting for rest countdown surfaces.
public enum RestTimerFormatting {
    public static func mmss(_ remainingSeconds: Int) -> String {
        let clamped = max(0, remainingSeconds)
        let minutes = clamped / 60
        let seconds = clamped % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

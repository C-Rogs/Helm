import Foundation

/// Fires at most four ~25% set-completion milestones per workout session.
public enum SessionMilestonePolicy {
    public static let maxFiresPerSession = 4

    /// Returns the quartile (1...4) just crossed, or nil if none / already recorded / cap hit.
    public static func crossedMilestone(
        previousCompleted: Int,
        completed: Int,
        total: Int,
        alreadyFiredQuartiles: Set<Int>
    ) -> Int? {
        guard total > 0,
              completed > previousCompleted,
              alreadyFiredQuartiles.count < maxFiresPerSession else {
            return nil
        }

        let previousRatio = Double(previousCompleted) / Double(total)
        let currentRatio = Double(min(completed, total)) / Double(total)

        for quartile in 1...maxFiresPerSession {
            let threshold = Double(quartile) / Double(maxFiresPerSession)
            guard previousRatio < threshold, currentRatio >= threshold else { continue }
            guard !alreadyFiredQuartiles.contains(quartile) else { continue }
            return quartile
        }
        return nil
    }

    public static func message(forQuartile quartile: Int) -> String {
        switch quartile {
        case 1:
            return "About a quarter done. How do joints and the working muscle feel?"
        case 2:
            return "Halfway. Keep form tight; tell me if anything feels off."
        case 3:
            return "Three quarters. Finish strong, or ask if you want a safer swap."
        default:
            return "Session nearly done. Tell me about any pain or niggles and I can save a short recovery note to Memory."
        }
    }
}

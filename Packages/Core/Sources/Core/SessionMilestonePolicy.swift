import Foundation

/// Fires at most four ~25% set-completion milestones per workout session.
/// Visible toast uses short copy; coach peek / chat keep the longer prompt.
public enum SessionMilestonePolicy {
    public static let maxFiresPerSession = 4

    /// Empty / ad-hoc sessions grow as the athlete adds lifts. Quartiles against a moving total are noise.
    public static func applies(to source: WorkoutSessionSource) -> Bool {
        switch source {
        case .prescription, .template, .importSource:
            return true
        case .manual, .healthKit:
            return false
        }
    }

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

    /// Short title for the in-workout toast (not the PR celebration sheet).
    public static func toastTitle(forQuartile quartile: Int) -> String {
        switch quartile {
        case 1:
            return "Quarter done"
        case 2:
            return "Halfway"
        case 3:
            return "Three quarters"
        default:
            return "Nearly done"
        }
    }

    /// One-line body under the toast title.
    public static func toastMessage(forQuartile quartile: Int) -> String {
        switch quartile {
        case 1:
            return "About 25% through. Check joints and the working muscle."
        case 2:
            return "Keep form tight. Tell coach if anything feels off."
        case 3:
            return "Finish strong, or ask for a safer swap."
        default:
            return "Note any pain or niggles before you leave."
        }
    }

    /// Longer coach-facing prompt for peek / chat / push.
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

    /// Optional finish-summary line listing checkpoints that fired this session.
    public static func finishRecap(firedQuartiles: Set<Int>) -> String? {
        let ordered = (1...maxFiresPerSession).filter { firedQuartiles.contains($0) }
        guard !ordered.isEmpty else { return nil }
        let labels = ordered.map { toastTitle(forQuartile: $0) }
        return "Checkpoints hit: \(labels.joined(separator: ", "))."
    }
}

import Foundation

/// Redistributes weekly hard-set targets when the athlete picks focus muscles.
///
/// Formula (empty or invalid priorities → identity on base targets):
/// 1. `Base_m` = accumulating/deload weekly hard-set target for each muscle in the mesocycle.
/// 2. Cap priorities to the first 1…3 unique `MuscleGroup`s (order preserved).
/// 3. Boost each priority: `B_p = clamp(round(Base_p * boostFactor), MEV…MRV)`.
/// 4. Let `surplus = Σ(B_p − Base_p)`. Non-priorities absorb that surplus cut
///    proportional to their base:
///    `R_n = clamp(round(Base_n − surplus * Base_n / ΣBase_non), MEV…MRV)`.
/// 5. If MEV floors block the full cut, residual surplus stays; total weekly sets
///    may rise slightly. Never raise a non-priority above its base in this step.
///
/// `boostFactor` is 1.20 (+20% uplift per focus muscle before landmark clamp).
public enum MusclePriorityRedistribution {
    public static let boostFactor = 1.20
    public static let maxPriorities = 3

    public static func normalize(_ priorities: [MuscleGroup]) -> [MuscleGroup] {
        var seen = Set<MuscleGroup>()
        var out: [MuscleGroup] = []
        for muscle in priorities where !seen.contains(muscle) {
            seen.insert(muscle)
            out.append(muscle)
            if out.count == maxPriorities { break }
        }
        return out
    }

    /// Apply priority boost + non-priority shrink to already-computed base targets.
    ///
    /// - Parameters:
    ///   - baseTargets: Unprioritized weekly hard-set targets keyed by muscle.
    ///   - landmarks: MEV/MRV used to clamp; missing entries skip landmark clamp
    ///     (still participate in surplus math using unclamped values).
    ///   - priorities: Focus muscles (capped to 1…3 unique).
    public static func redistribute(
        baseTargets: [MuscleGroup: Int],
        landmarks: [MuscleGroup: VolumeLandmarks],
        priorities: [MuscleGroup]
    ) -> [MuscleGroup: Int] {
        let focus = normalize(priorities).filter { baseTargets[$0] != nil }
        guard !focus.isEmpty else { return baseTargets }

        var result = baseTargets
        var surplus = 0

        for muscle in focus {
            guard let base = baseTargets[muscle] else { continue }
            let boosted = Int((Double(base) * boostFactor).rounded())
            let clamped = clamp(boosted, landmarks: landmarks[muscle])
            result[muscle] = clamped
            surplus += clamped - base
        }

        guard surplus > 0 else { return result }

        let nonPriority = baseTargets.keys.filter { !focus.contains($0) }
        let nonPriorityBaseSum = nonPriority.reduce(0) { $0 + (baseTargets[$1] ?? 0) }
        guard nonPriorityBaseSum > 0 else { return result }

        for muscle in nonPriority {
            guard let base = baseTargets[muscle] else { continue }
            let share = Double(surplus) * Double(base) / Double(nonPriorityBaseSum)
            let reduced = Int((Double(base) - share).rounded())
            let floored = clamp(min(base, reduced), landmarks: landmarks[muscle])
            result[muscle] = floored
        }

        return result
    }

    private static func clamp(_ value: Int, landmarks: VolumeLandmarks?) -> Int {
        guard let landmarks else { return max(0, value) }
        return min(landmarks.mrv, max(landmarks.mev, value))
    }
}

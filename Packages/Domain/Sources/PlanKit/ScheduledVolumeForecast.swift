import Foundation

/// Estimates hard sets still on the calendar for each muscle ("scheduled" volume).
///
/// Simulates upcoming sessions in order using a per-muscle remaining/sessions split.
/// This is a Trends projection heuristic, not a full MPSC replay. Slot floors and
/// synergist caps live in SessionSetAllocator / HardSetAccounting for live prescription.
public enum ScheduledVolumeForecast {
    /// Per-muscle scheduled hard-set totals for an ordered list of upcoming session muscle lists.
    ///
    /// - Parameters:
    ///   - weeklyTargets: Mesocycle weekly hard-set targets.
    ///   - loggedSets: Hard sets already counted in the load window.
    ///   - upcomingTargetMuscles: One entry per upcoming session day, muscles trained that day.
    public static func scheduledSets(
        weeklyTargets: [MuscleGroup: Int],
        loggedSets: [MuscleGroup: Double],
        upcomingTargetMuscles: [[MuscleGroup]]
    ) -> [MuscleGroup: Double] {
        var simulatedDone = loggedSets
        var scheduled: [MuscleGroup: Double] = [:]

        for (index, muscles) in upcomingTargetMuscles.enumerated() {
            let uniqueMuscles = Array(Set(muscles))
            for muscle in uniqueMuscles {
                guard let targetInt = weeklyTargets[muscle], targetInt > 0 else { continue }
                let target = Double(targetInt)
                let done = simulatedDone[muscle, default: 0]
                let remaining = max(0, target - done)
                let sessionsLeft = upcomingTargetMuscles[index...]
                    .filter { $0.contains(muscle) }
                    .count
                let baseSets = max(1, Int(ceil(remaining / Double(max(sessionsLeft, 1)))))
                let amount = Double(baseSets)
                scheduled[muscle, default: 0] += amount
                simulatedDone[muscle, default: 0] += amount
            }
        }

        return scheduled
    }
}

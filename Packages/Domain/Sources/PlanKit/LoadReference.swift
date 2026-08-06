import Core
import Foundation

/// Rolling best-effort 1RM per exercise, used to decide whether a logged load was a warmup.
///
/// Grading a set against a reference that includes that same set is circular: a lifter's
/// heaviest-ever single always reads as exactly 100% of their 1RM, and a whole session of
/// light work silently redefines what "light" means. The accumulator only ever exposes
/// evidence from strictly earlier sessions.
struct LoadReferenceAccumulator {
    private struct Entry {
        var kilograms: Double
        var loggedAt: Date
    }

    private var best: [String: Entry] = [:]
    private let policy: HardSetPolicy

    init(policy: HardSetPolicy = .standard) {
        self.policy = policy
    }

    /// Fold a session's sets into the reference. Call after grading that session, never before.
    mutating func ingest(_ session: WorkoutSession) {
        for set in session.sets {
            guard let reps = set.reps, reps > 0, reps <= policy.maxRepsForE1RMEstimate else { continue }
            guard let mass = set.mass, mass.kilograms > 0 else { continue }
            guard SetStimulusRole(set.setType) != .excluded else { continue }

            let estimate = ProgressionEngine.estimatedOneRepMax(mass: mass, reps: reps).kilograms
            guard estimate > 0 else { continue }

            if let existing = best[set.exerciseID], existing.kilograms >= estimate {
                continue
            }
            best[set.exerciseID] = Entry(kilograms: estimate, loggedAt: set.completedAt)
        }
    }

    /// Reference 1RM as of `date`, decayed for time away from the lift.
    ///
    /// Without decay a PR from two years ago makes today's honest working weight look like
    /// warmup-intensity noise and silently deletes it from the ledger.
    func context(asOf date: Date) -> HardSetEvaluationContext {
        var resolved: [String: Mass] = [:]
        for (exerciseID, entry) in best {
            let decayed = decayedKilograms(entry, asOf: date)
            guard decayed > 0 else { continue }
            resolved[exerciseID] = Mass(kilograms: decayed)
        }
        return HardSetEvaluationContext(estimatedOneRepMaxByExercise: resolved)
    }

    private func decayedKilograms(_ entry: Entry, asOf date: Date) -> Double {
        let elapsedDays = date.timeIntervalSince(entry.loggedAt) / 86_400
        guard elapsedDays > policy.e1rmDecayGraceDays else { return entry.kilograms }
        let overdue = elapsedDays - policy.e1rmDecayGraceDays
        return entry.kilograms * exp(-policy.e1rmDecayPerDay * overdue)
    }
}

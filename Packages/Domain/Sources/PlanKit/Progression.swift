import Core
import Foundation

/// Why today's working weight was chosen relative to the last logged session.
public enum LoadDecision: String, Sendable, Hashable, Codable {
    case coldStart = "cold_start"
    case hold = "hold"
    case bump = "bump"
    case stallBackoff = "stall_backoff"
}

/// Per-lift progression targets derived from logged history.
public struct LiftProgression: Sendable, Hashable, Codable {
    public let exerciseID: String
    public let estimatedOneRepMax: Mass?
    public let workingWeight: Mass?
    /// Hypertrophy scheme floor (compound 8, isolation 10). Used after load changes.
    public let schemeRepMin: Int
    /// Hypertrophy scheme ceiling. Hitting this with spare RIR bumps load.
    public let schemeRepMax: Int
    /// Today's prescribed reps. Equal to `targetRepMax`. Engine fills the row, not a range.
    public let targetRepMin: Int
    public let targetRepMax: Int
    public let isStalledBackoff: Bool
    public let loadDecision: LoadDecision
    public let lastSessionWeight: Mass?

    public init(
        exerciseID: String,
        estimatedOneRepMax: Mass? = nil,
        workingWeight: Mass? = nil,
        schemeRepMin: Int = 8,
        schemeRepMax: Int = 12,
        targetRepMin: Int = 8,
        targetRepMax: Int = 12,
        isStalledBackoff: Bool = false,
        loadDecision: LoadDecision = .coldStart,
        lastSessionWeight: Mass? = nil
    ) {
        self.exerciseID = exerciseID
        self.estimatedOneRepMax = estimatedOneRepMax
        self.workingWeight = workingWeight
        self.schemeRepMin = schemeRepMin
        self.schemeRepMax = schemeRepMax
        self.targetRepMin = targetRepMin
        self.targetRepMax = targetRepMax
        self.isStalledBackoff = isStalledBackoff
        self.loadDecision = loadDecision
        self.lastSessionWeight = lastSessionWeight
    }
}

/// Compound vs isolation progression style.
enum LiftKind: Sendable, Hashable {
    case compound
    case isolation

    var repRange: (min: Int, max: Int) {
        switch self {
        case .compound: (8, 12)
        case .isolation: (10, 15)
        }
    }

    var weightBumpFraction: Double {
        switch self {
        case .compound: 0.025
        case .isolation: 0.0125
        }
    }

    var loadIncrement: LoadIncrement {
        switch self {
        case .compound: .barbell
        case .isolation: .dumbbell
        }
    }
}

enum ProgressionEngine {
    static let defaultRepMin = 8
    static let defaultRepMax = 12
    /// Sets above this rep count are excluded when picking a reference e1RM from history.
    static let referenceRepCap = 12
    static let stallBackoffFraction = 0.10
    /// Balanced-day target (RPE 8). PrescriptionEngine overrides from readiness gating.
    static let defaultTargetRIR = 2.0

    static func liftKind(exerciseID: String, muscleMap: ExerciseMuscleMap?) -> LiftKind {
        let id = exerciseID.lowercased()
        let isolationKeywords = [
            "curl", "extension", "fly", "flye", "raise", "kickback",
            "pullover", "pushdown", "crunch", "calf"
        ]
        let compoundKeywords = [
            "press", "squat", "deadlift", "row", "pullup", "pull-up", "lunge", "rdl"
        ]
        if isolationKeywords.contains(where: { id.contains($0) }) {
            return .isolation
        }
        if compoundKeywords.contains(where: { id.contains($0) }) {
            return .compound
        }
        if let muscleMap, muscleMap.contributions.count == 1,
           muscleMap.contributions[0].isDirect {
            return .isolation
        }
        return .compound
    }

    /// Epley estimated 1RM from a single logged set.
    static func estimatedOneRepMax(mass: Mass, reps: Int) -> Mass {
        let e1rmKg = mass.kilograms * (1.0 + Double(reps) / 30.0)
        return Mass(kilograms: e1rmKg)
    }

    static func bestEstimatedOneRepMax(from sets: [LoggedSet]) -> Mass? {
        let working = sets.filter {
            !$0.isWarmup
                && $0.mass != nil
                && $0.reps != nil
                && ($0.reps ?? 0) <= referenceRepCap
        }
        guard !working.isEmpty else { return nil }
        return working.map { set in
            estimatedOneRepMax(mass: set.mass!, reps: set.reps!)
        }.max(by: { $0.kilograms < $1.kilograms })
    }

    static func progression(
        for exerciseID: String,
        history: [LoggedSet],
        muscleMap: ExerciseMuscleMap? = nil,
        loadIncrement: LoadIncrement? = nil,
        targetRIR: Double = defaultTargetRIR
    ) -> LiftProgression {
        let kind = liftKind(exerciseID: exerciseID, muscleMap: muscleMap)
        let increment = loadIncrement ?? kind.loadIncrement
        let schemeMin = kind.repRange.min
        let schemeMax = kind.repRange.max

        let exerciseSets = history
            .filter { $0.exerciseID == exerciseID }
            .sorted { $0.completedAt < $1.completedAt }

        let e1rm = bestEstimatedOneRepMax(from: exerciseSets)
        let workingSets = exerciseSets.filter { !$0.isWarmup && $0.mass != nil && $0.reps != nil }

        guard let latest = workingSets.last else {
            return LiftProgression(
                exerciseID: exerciseID,
                estimatedOneRepMax: e1rm,
                workingWeight: nil,
                schemeRepMin: schemeMin,
                schemeRepMax: schemeMax,
                targetRepMin: schemeMin,
                targetRepMax: schemeMin,
                loadDecision: .coldStart,
                lastSessionWeight: nil
            )
        }

        let currentWeight = latest.mass!
        let sessions = SessionGrouping.groupIntoSessions(workingSets)
        let latestSessionSets = sessions.last ?? []
        let lastSessionWeight = sessionWorkingWeight(latestSessionSets) ?? currentWeight

        let stalled = isStalled(sessions: sessions, repMax: schemeMax)

        let nextWeight: Mass
        let isStalledBackoff: Bool
        let loadDecision: LoadDecision
        if stalled {
            let reduced = Mass(kilograms: currentWeight.kilograms * (1.0 - stallBackoffFraction))
            nextWeight = LoadRounding.snapProgression(
                from: currentWeight,
                proposed: reduced,
                increment: increment
            )
            isStalledBackoff = true
            loadDecision = .stallBackoff
        } else {
            let hitTopOfRange = latestSessionSets.allSatisfy { set in
                guard let reps = set.reps else { return false }
                return reps >= schemeMax
            }
            let recoveredEnough = latestSessionSets.allSatisfy { set in
                guard let rir = proximityRIR(set) else { return true }
                return rir >= 1
            }

            if hitTopOfRange && recoveredEnough {
                let bumped = Mass(kilograms: currentWeight.kilograms * (1.0 + kind.weightBumpFraction))
                nextWeight = LoadRounding.snapProgression(
                    from: currentWeight,
                    proposed: bumped,
                    increment: increment
                )
                loadDecision = .bump
            } else {
                nextWeight = currentWeight
                loadDecision = .hold
            }
            isStalledBackoff = false
        }

        let prescribedReps = nextPrescribedReps(
            latestSessionSets: latestSessionSets,
            schemeMin: schemeMin,
            schemeMax: schemeMax,
            loadDecision: loadDecision,
            targetRIR: targetRIR
        )

        return LiftProgression(
            exerciseID: exerciseID,
            estimatedOneRepMax: e1rm,
            workingWeight: nextWeight,
            schemeRepMin: schemeMin,
            schemeRepMax: schemeMax,
            targetRepMin: prescribedReps,
            targetRepMax: prescribedReps,
            isStalledBackoff: isStalledBackoff,
            loadDecision: loadDecision,
            lastSessionWeight: lastSessionWeight
        )
    }

    /// Engine owns the next-session assignment. Rows get this number, not the scheme floor.
    ///
    /// Load bump / backoff / cold start reset to `schemeMin`. Otherwise climb from the
    /// hardest set last time: easy (spare RIR >= 2) skips ahead; on-target adds 1;
    /// failure or a clear RPE overshoot holds.
    static func nextPrescribedReps(
        latestSessionSets: [LoggedSet],
        schemeMin: Int,
        schemeMax: Int,
        loadDecision: LoadDecision,
        targetRIR: Double
    ) -> Int {
        switch loadDecision {
        case .coldStart, .bump, .stallBackoff:
            return schemeMin
        case .hold:
            break
        }

        let loggedReps = latestSessionSets.compactMap(\.reps)
        guard let lastReps = loggedReps.min() else { return schemeMin }

        let rirs = latestSessionSets.compactMap(proximityRIR)
        let hardestRIR = rirs.min() ?? targetRIR
        let climbed = lastReps + nextRepAdd(hardestRIR: hardestRIR, targetRIR: targetRIR)
        return min(schemeMax, max(schemeMin, climbed))
    }

    static func nextRepAdd(hardestRIR: Double, targetRIR: Double) -> Int {
        if hardestRIR < 1 { return 0 }
        let spare = hardestRIR - targetRIR
        if spare >= 2 { return Int(spare.rounded(.down)) }
        if spare >= -0.5 { return 1 }
        return 0
    }

    static func proximityRIR(_ set: LoggedSet) -> Double? {
        if let rir = set.rir { return Double(rir) }
        if let rpe = set.rpe { return RIRConsistency.rirFromRPE(rpe) }
        return nil
    }

    private static func isStalled(sessions: [[LoggedSet]], repMax: Int) -> Bool {
        guard sessions.count >= 2 else { return false }
        let previous = sessions[sessions.count - 2]
        let latest = sessions[sessions.count - 1]
        guard let previousWeight = sessionWorkingWeight(previous),
              let latestWeight = sessionWorkingWeight(latest),
              previousWeight.kilograms == latestWeight.kilograms else {
            return false
        }
        // Sitting below the top of the rep range is ordinary double progression, not a
        // stall. A stall is the same load buying no extra reps, so 8/8/8 followed by
        // 9/9/9 must keep climbing rather than trigger a back-off.
        guard sessionMissedRepTarget(latest, repMax: repMax) else { return false }
        return totalReps(latest) <= totalReps(previous)
    }

    private static func totalReps(_ session: [LoggedSet]) -> Int {
        session.reduce(0) { $0 + ($1.reps ?? 0) }
    }

    private static func sessionWorkingWeight(_ session: [LoggedSet]) -> Mass? {
        session.compactMap(\.mass).max(by: { $0.kilograms < $1.kilograms })
    }

    private static func sessionMissedRepTarget(_ session: [LoggedSet], repMax: Int) -> Bool {
        let sets = session.filter { $0.mass != nil && $0.reps != nil }
        guard !sets.isEmpty else { return false }
        return !sets.allSatisfy { ($0.reps ?? 0) >= repMax }
    }
}

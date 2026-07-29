import Foundation

/// Weekly emphasis-muscle volume tracked against MEV landmarks (for example arm emphasis).
public struct EmphasisVolumeProgress: Sendable, Hashable, Equatable {
    public let label: String
    public let doneSets: Int
    public let targetSets: Int

    public init(label: String, doneSets: Int, targetSets: Int) {
        self.label = label
        self.doneSets = doneSets
        self.targetSets = targetSets
    }

    public var displayText: String {
        "\(label) · \(doneSets)/\(targetSets) sets this week"
    }

    public var hasMetFloor: Bool {
        doneSets >= targetSets
    }
}

public enum EmphasisVolumePolicy {
    public static func supplementaryMuscles(for emphasis: String?) -> [MuscleGroup] {
        trackedMuscles(for: emphasis)
    }

    public static func trackedMuscles(for emphasis: String?) -> [MuscleGroup] {
        let normalized = emphasis?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        guard !normalized.isEmpty else { return [] }

        if normalized.contains("arm") {
            return [.biceps, .triceps]
        }
        if normalized.contains("leg") {
            return [.quads, .hamstrings]
        }
        if normalized.contains("v-taper") || normalized.contains("vtaper") {
            return [.shoulders, .back]
        }
        return []
    }

    public static func emphasisLabel(for emphasis: String?) -> String? {
        let normalized = emphasis?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        guard !normalized.isEmpty else { return nil }

        if normalized.contains("arm") {
            return "Arm emphasis"
        }
        if normalized.contains("leg") {
            return "Leg emphasis"
        }
        if normalized.contains("v-taper") || normalized.contains("vtaper") {
            return "V-taper emphasis"
        }
        return emphasis?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func augmentedTargetMuscles(
        base: [MuscleGroup],
        emphasis: String?
    ) -> [MuscleGroup] {
        let extras = supplementaryMuscles(for: emphasis)
        guard !extras.isEmpty else { return base }

        var result = base
        for muscle in extras where !result.contains(muscle) {
            result.append(muscle)
        }
        return result
    }

    public static func mevFloor(
        for muscles: [MuscleGroup],
        mesocycleState: MesocycleState
    ) -> Int {
        muscles.reduce(0) { partial, muscle in
            partial + (mesocycleState.muscles[muscle]?.landmarks.mev ?? 0)
        }
    }

    public static func weeklyProgress(
        emphasis: String?,
        ledger: WeeklyHardSetLedger,
        mesocycleState: MesocycleState
    ) -> EmphasisVolumeProgress? {
        guard let label = emphasisLabel(for: emphasis) else { return nil }
        let muscles = trackedMuscles(for: emphasis)
        guard !muscles.isEmpty else { return nil }

        let target = mevFloor(for: muscles, mesocycleState: mesocycleState)
        guard target > 0 else { return nil }

        let done = muscles.reduce(0.0) { partial, muscle in
            partial + ledger.totals[muscle, default: 0]
        }

        return EmphasisVolumeProgress(
            label: label,
            doneSets: Int(done.rounded(.down)),
            targetSets: target
        )
    }

    /// Minimum hard sets to prescribe for `muscle` this session so emphasis muscles reach MEV by week end.
    public static func minimumSetsThisSession(
        for muscle: MuscleGroup,
        emphasis: String?,
        ledger: WeeklyHardSetLedger,
        mesocycleState: MesocycleState,
        remainingSessionsThisWeek: Int
    ) -> Int? {
        let tracked = trackedMuscles(for: emphasis)
        guard tracked.contains(muscle) else { return nil }
        guard let muscleState = mesocycleState.muscles[muscle] else { return nil }

        let mev = muscleState.landmarks.mev
        let done = ledger.totals[muscle, default: 0]
        guard done < Double(mev) else { return nil }

        let remaining = Double(mev) - done
        let sessions = max(1, remainingSessionsThisWeek)
        return max(1, Int(ceil(remaining / Double(sessions))))
    }
}

import Foundation

public struct MesocycleMuscleRow: Sendable, Hashable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public let currentWeek: Int
    public let blockLengthWeeks: Int
    public let phaseLabel: String
    public let weeklyTarget: Int
    public let weeklyDone: Double
    public let mev: Int
    public let mrv: Int
    public let state: HelmState

    public init(
        id: String,
        label: String,
        currentWeek: Int,
        blockLengthWeeks: Int,
        phaseLabel: String,
        weeklyTarget: Int,
        weeklyDone: Double,
        mev: Int,
        mrv: Int,
        state: HelmState
    ) {
        self.id = id
        self.label = label
        self.currentWeek = currentWeek
        self.blockLengthWeeks = blockLengthWeeks
        self.phaseLabel = phaseLabel
        self.weeklyTarget = weeklyTarget
        self.weeklyDone = weeklyDone
        self.mev = mev
        self.mrv = mrv
        self.state = state
    }
}

public struct ProgressionSchemeSummary: Sendable, Hashable, Equatable {
    public let repRange: String
    public let rpeCap: String
    public let targetRPE: String
    public let loadIncrement: String
    public let setsPerSession: String

    public init(
        repRange: String,
        rpeCap: String,
        targetRPE: String,
        loadIncrement: String,
        setsPerSession: String
    ) {
        self.repRange = repRange
        self.rpeCap = rpeCap
        self.targetRPE = targetRPE
        self.loadIncrement = loadIncrement
        self.setsPerSession = setsPerSession
    }
}

public struct LiftLadderStep: Sendable, Hashable, Equatable, Identifiable {
    public let id: String
    public let stepIndex: Int
    public let title: String
    public let e1RMKilograms: Double?
    public let deltaKilograms: Double?
    public let isCompleted: Bool
    public let achievedAtLabel: String?

    public init(
        id: String,
        stepIndex: Int,
        title: String,
        e1RMKilograms: Double?,
        deltaKilograms: Double?,
        isCompleted: Bool,
        achievedAtLabel: String?
    ) {
        self.id = id
        self.stepIndex = stepIndex
        self.title = title
        self.e1RMKilograms = e1RMKilograms
        self.deltaKilograms = deltaKilograms
        self.isCompleted = isCompleted
        self.achievedAtLabel = achievedAtLabel
    }
}

public struct LiftLadderRow: Sendable, Hashable, Equatable, Identifiable {
    public let id: String
    public let displayName: String
    public let currentE1RMKilograms: Double?
    public let workingWeightKilograms: Double?
    public let targetRepRange: String
    public let steps: [LiftLadderStep]

    public init(
        id: String,
        displayName: String,
        currentE1RMKilograms: Double?,
        workingWeightKilograms: Double?,
        targetRepRange: String,
        steps: [LiftLadderStep]
    ) {
        self.id = id
        self.displayName = displayName
        self.currentE1RMKilograms = currentE1RMKilograms
        self.workingWeightKilograms = workingWeightKilograms
        self.targetRepRange = targetRepRange
        self.steps = steps
    }
}

public struct ProgressionDetailModel: Sendable, Hashable, Equatable {
    public let phaseLabel: String
    public let experienceLabel: String
    public let blockSummary: String
    public let isDeloadWeek: Bool
    public let muscles: [MesocycleMuscleRow]
    public let scheme: ProgressionSchemeSummary
    public let ladders: [LiftLadderRow]
    public let isColdStart: Bool

    public init(
        phaseLabel: String,
        experienceLabel: String,
        blockSummary: String,
        isDeloadWeek: Bool,
        muscles: [MesocycleMuscleRow],
        scheme: ProgressionSchemeSummary,
        ladders: [LiftLadderRow],
        isColdStart: Bool
    ) {
        self.phaseLabel = phaseLabel
        self.experienceLabel = experienceLabel
        self.blockSummary = blockSummary
        self.isDeloadWeek = isDeloadWeek
        self.muscles = muscles
        self.scheme = scheme
        self.ladders = ladders
        self.isColdStart = isColdStart
    }
}

public enum ProgressionDetailSnapshot {
    public static func text(for model: ProgressionDetailModel) -> String {
        var lines: [String] = [
            "# Progression",
            "## Block",
            "phase=\(model.phaseLabel)",
            "experience=\(model.experienceLabel)",
            "summary=\(model.blockSummary)",
            "deload=\(model.isDeloadWeek)",
            "coldStart=\(model.isColdStart)",
            "## Scheme",
            "repRange=\(model.scheme.repRange)",
            "rpeCap=\(model.scheme.rpeCap)",
            "targetRPE=\(model.scheme.targetRPE)",
            "loadIncrement=\(model.scheme.loadIncrement)",
            "setsPerSession=\(model.scheme.setsPerSession)",
            "## Mesocycle"
        ]

        if model.muscles.isEmpty {
            lines.append("- none")
        } else {
            for muscle in model.muscles {
                lines.append(
                    "- \(muscle.label): week \(muscle.currentWeek)/\(muscle.blockLengthWeeks) | \(muscle.phaseLabel) | target \(muscle.weeklyTarget) | done \(Int(muscle.weeklyDone.rounded())) | MEV \(muscle.mev) MRV \(muscle.mrv) | state=\(muscle.state.rawValue)"
                )
            }
        }

        lines.append("## Ladders")
        if model.ladders.isEmpty {
            lines.append("- none")
        } else {
            for ladder in model.ladders {
                lines.append("- \(ladder.displayName): e1RM=\(format(ladder.currentE1RMKilograms)) working=\(format(ladder.workingWeightKilograms)) reps=\(ladder.targetRepRange)")
                if ladder.steps.isEmpty {
                    lines.append("  steps=none")
                } else {
                    for step in ladder.steps {
                        let delta = step.deltaKilograms.map { format($0) } ?? "nil"
                        let e1rm = step.e1RMKilograms.map { format($0) } ?? "nil"
                        lines.append(
                            "  - step \(step.stepIndex): \(step.title) | e1RM=\(e1rm) | delta=\(delta) | completed=\(step.isCompleted)"
                        )
                    }
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func format(_ value: Double?) -> String {
        guard let value else { return "nil" }
        return String(format: "%.1f", value)
    }
}

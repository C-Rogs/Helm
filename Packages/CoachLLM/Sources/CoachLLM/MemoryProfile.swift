import Core
import Foundation

/// Durable coach memory Cameron can inspect and edit in Settings.
public struct MemoryProfile: Sendable, Hashable, Codable, Equatable {
    public var baselinesSummary: String
    public var mesocyclePosition: String
    public var phaseGoal: PhaseGoal?
    public var preferences: String
    public var standingConstraints: String
    public var whatHasWorked: String
    public var activeModules: [String]
    public var injuryHistory: String
    public var trainingResponses: String
    public var nutritionPatterns: String

    public init(
        baselinesSummary: String = "",
        mesocyclePosition: String = "",
        phaseGoal: PhaseGoal? = nil,
        preferences: String = "",
        standingConstraints: String = "",
        whatHasWorked: String = "",
        activeModules: [String] = [],
        injuryHistory: String = "",
        trainingResponses: String = "",
        nutritionPatterns: String = ""
    ) {
        self.baselinesSummary = baselinesSummary
        self.mesocyclePosition = mesocyclePosition
        self.phaseGoal = phaseGoal
        self.preferences = preferences
        self.standingConstraints = standingConstraints
        self.whatHasWorked = whatHasWorked
        self.activeModules = activeModules
        self.injuryHistory = injuryHistory
        self.trainingResponses = trainingResponses
        self.nutritionPatterns = nutritionPatterns
    }

    public static let empty = MemoryProfile()

    /// Deterministic text block for implicit LLM prefix caching. Omits timestamps.
    public func stablePrefixText() -> String {
        let sections = [
            "## Baselines\n\(Self.normalized(baselinesSummary))",
            "## Mesocycle\n\(Self.normalized(mesocyclePosition))",
            "## Phase\n\(Self.phaseStableLine(phaseGoal))",
            "## Preferences\n\(Self.normalized(preferences))",
            "## Standing Constraints\n\(Self.normalized(standingConstraints))",
            "## What Has Worked\n\(Self.normalized(whatHasWorked))",
            activeModulesSection(),
            injuryHistorySection(),
            trainingResponsesSection(),
            nutritionPatternsSection()
        ]
        return sections.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    private func activeModulesSection() -> String {
        guard !activeModules.isEmpty else { return "" }
        return "## Active Modules\n\(activeModules.joined(separator: ", "))"
    }

    private func injuryHistorySection() -> String {
        let text = Self.normalized(injuryHistory)
        guard !text.isEmpty else { return "" }
        return "## Injury History\n\(text)"
    }

    private func trainingResponsesSection() -> String {
        let text = Self.normalized(trainingResponses)
        guard !text.isEmpty else { return "" }
        return "## Training Responses\n\(text)"
    }

    private func nutritionPatternsSection() -> String {
        let text = Self.normalized(nutritionPatterns)
        guard !text.isEmpty else { return "" }
        return "## Nutrition Patterns\n\(text)"
    }

    /// One-line phase/goal for follow-up turns (token-cheap continuity).
    public func slimPhaseLine() -> String {
        Self.phaseStableLine(phaseGoal)
    }

    /// Standing constraints only, for follow-up / in-session context.
    public func slimStandingConstraintsText() -> String {
        Self.normalized(standingConstraints)
    }

    private static func normalized(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func phaseStableLine(_ goal: PhaseGoal?) -> String {
        guard let goal else { return "" }
        var parts = ["phase=\(goal.phase.rawValue)"]
        if let weeklyRateKg = goal.weeklyRateKg {
            parts.append("weeklyRateKg=\(Self.stableNumber(weeklyRateKg))")
        }
        if let targetMass = goal.targetMass {
            parts.append("targetMassKg=\(Self.stableNumber(targetMass.kilograms))")
        }
        if let emphasis = goal.emphasis, !emphasis.isEmpty {
            parts.append("emphasis=\(emphasis)")
        }
        return parts.joined(separator: "\n")
    }

    private static func stableNumber(_ value: Double) -> String {
        String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), value)
            .replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
    }
}

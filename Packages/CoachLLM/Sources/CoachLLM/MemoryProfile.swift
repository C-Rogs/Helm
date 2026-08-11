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
    /// Pending memory refinements extracted from recent conversations,
    /// awaiting athlete confirmation.
    public var pendingRefinements: [MemoryRefinementEntry]
    /// Coach voice/communication style -- learned implicitly or set explicitly.
    public var globalStyle: CoachStyleProfile?
    public var trainingStyle: CoachStyleProfile?
    public var nutritionStyle: CoachStyleProfile?
    public var recoveryStyle: CoachStyleProfile?

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
        nutritionPatterns: String = "",
        pendingRefinements: [MemoryRefinementEntry] = [],
        globalStyle: CoachStyleProfile? = nil,
        trainingStyle: CoachStyleProfile? = nil,
        nutritionStyle: CoachStyleProfile? = nil,
        recoveryStyle: CoachStyleProfile? = nil
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
        self.pendingRefinements = pendingRefinements
        self.globalStyle = globalStyle
        self.trainingStyle = trainingStyle
        self.nutritionStyle = nutritionStyle
        self.recoveryStyle = recoveryStyle
    }

    public static let empty = MemoryProfile()

    enum CodingKeys: String, CodingKey {
        case baselinesSummary
        case mesocyclePosition
        case phaseGoal
        case preferences
        case standingConstraints
        case whatHasWorked
        case activeModules
        case injuryHistory
        case trainingResponses
        case nutritionPatterns
        case pendingRefinements
        case globalStyle
        case trainingStyle
        case nutritionStyle
        case recoveryStyle
    }

    /// Lenient decode so older on-disk profiles missing newer fields still load.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        baselinesSummary = try container.decodeIfPresent(String.self, forKey: .baselinesSummary) ?? ""
        mesocyclePosition = try container.decodeIfPresent(String.self, forKey: .mesocyclePosition) ?? ""
        phaseGoal = try container.decodeIfPresent(PhaseGoal.self, forKey: .phaseGoal)
        preferences = try container.decodeIfPresent(String.self, forKey: .preferences) ?? ""
        standingConstraints = try container.decodeIfPresent(String.self, forKey: .standingConstraints) ?? ""
        whatHasWorked = try container.decodeIfPresent(String.self, forKey: .whatHasWorked) ?? ""
        activeModules = try container.decodeIfPresent([String].self, forKey: .activeModules) ?? []
        injuryHistory = try container.decodeIfPresent(String.self, forKey: .injuryHistory) ?? ""
        trainingResponses = try container.decodeIfPresent(String.self, forKey: .trainingResponses) ?? ""
        nutritionPatterns = try container.decodeIfPresent(String.self, forKey: .nutritionPatterns) ?? ""
        pendingRefinements = try container.decodeIfPresent([MemoryRefinementEntry].self, forKey: .pendingRefinements) ?? []
        globalStyle = try container.decodeIfPresent(CoachStyleProfile.self, forKey: .globalStyle)
        trainingStyle = try container.decodeIfPresent(CoachStyleProfile.self, forKey: .trainingStyle)
        nutritionStyle = try container.decodeIfPresent(CoachStyleProfile.self, forKey: .nutritionStyle)
        recoveryStyle = try container.decodeIfPresent(CoachStyleProfile.self, forKey: .recoveryStyle)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(baselinesSummary, forKey: .baselinesSummary)
        try container.encode(mesocyclePosition, forKey: .mesocyclePosition)
        try container.encodeIfPresent(phaseGoal, forKey: .phaseGoal)
        try container.encode(preferences, forKey: .preferences)
        try container.encode(standingConstraints, forKey: .standingConstraints)
        try container.encode(whatHasWorked, forKey: .whatHasWorked)
        try container.encode(activeModules, forKey: .activeModules)
        try container.encode(injuryHistory, forKey: .injuryHistory)
        try container.encode(trainingResponses, forKey: .trainingResponses)
        try container.encode(nutritionPatterns, forKey: .nutritionPatterns)
        try container.encode(pendingRefinements, forKey: .pendingRefinements)
        try container.encodeIfPresent(globalStyle, forKey: .globalStyle)
        try container.encodeIfPresent(trainingStyle, forKey: .trainingStyle)
        try container.encodeIfPresent(nutritionStyle, forKey: .nutritionStyle)
        try container.encodeIfPresent(recoveryStyle, forKey: .recoveryStyle)
    }

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

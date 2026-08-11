import Foundation

/// Coach voice adaptation profile. Learned implicitly from athlete communication
/// patterns or set explicitly in Settings.
public struct CoachStyleProfile: Sendable, Hashable, Codable, Equatable {
    public var detail: Detail
    public var depth: Depth
    public var encouragement: Encouragement
    public var directive: Directive
    public var lastUpdated: Date
    public var source: Source

    public init(
        detail: Detail = .balanced,
        depth: Depth = .mixed,
        encouragement: Encouragement = .balanced,
        directive: Directive = .balanced,
        lastUpdated: Date = .now,
        source: Source = .heuristic
    ) {
        self.detail = detail
        self.depth = depth
        self.encouragement = encouragement
        self.directive = directive
        self.lastUpdated = lastUpdated
        self.source = source
    }

    public enum Detail: String, Sendable, Hashable, Codable, CaseIterable {
        case brief
        case balanced
        case thorough
    }

    public enum Depth: String, Sendable, Hashable, Codable, CaseIterable {
        case lay
        case mixed
        case scientific
    }

    public enum Encouragement: String, Sendable, Hashable, Codable, CaseIterable {
        case neutral
        case balanced
        case supportive
    }

    public enum Directive: String, Sendable, Hashable, Codable, CaseIterable {
        case suggestive
        case balanced
        case prescriptive
    }

    public enum Source: String, Sendable, Hashable, Codable {
        case heuristic
        case explicit
    }

    /// Prompt-friendly delta block for system instructions.
    public var promptDelta: String {
        let parts = [
            "- Detail: \(detail.rawValue) (\(detail.contrastDescription))",
            "- Depth: \(depth.rawValue) (\(depth.contrastDescription))",
            "- Tone: \(encouragement.rawValue) (\(encouragement.contrastDescription))",
            "- Direction: \(directive.rawValue) (\(directive.contrastDescription))"
        ]
        return "## Athlete Voice Profile\n" + parts.joined(separator: "\n")
    }
}

extension CoachStyleProfile.Detail {
    public var contrastDescription: String {
        switch self {
        case .brief: return "not verbose, not exhaustive"
        case .balanced: return "not brief, not exhaustive"
        case .thorough: return "not brief, not rapid-fire"
        }
    }
}

extension CoachStyleProfile.Depth {
    public var contrastDescription: String {
        switch self {
        case .lay: return "avoid jargon, not technical"
        case .mixed: return "not purely lay, not purely scientific"
        case .scientific: return "use domain terms, cite mechanisms"
        }
    }
}

extension CoachStyleProfile.Encouragement {
    public var contrastDescription: String {
        switch self {
        case .neutral: return "direct, not chatty"
        case .balanced: return "supportive but not cheerleader"
        case .supportive: return "empathetic, not cold"
        }
    }
}

extension CoachStyleProfile.Directive {
    public var contrastDescription: String {
        switch self {
        case .suggestive: return "offer options, not prescribe"
        case .balanced: return "suggest with reasoning, don't just prescribe"
        case .prescriptive: return "give clear directions"
        }
    }
}

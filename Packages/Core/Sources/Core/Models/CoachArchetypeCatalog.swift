import Foundation

/// Coach-facing exercise archetype layer bundled beside the full engine catalog.
public struct CoachArchetypeCatalog: Sendable, Hashable, Codable, Equatable {
    public let schemaVersion: String
    public let generatedAt: String?
    public let archetypes: [CoachArchetype]
    public let mapping: [String: String]
    public let variants: [String: CoachArchetypeVariants]
    public let aliasSuggestions: [CoachArchetypeAliasSuggestion]?
    public let validation: CoachArchetypeValidation?

    public init(
        schemaVersion: String,
        generatedAt: String? = nil,
        archetypes: [CoachArchetype],
        mapping: [String: String],
        variants: [String: CoachArchetypeVariants],
        aliasSuggestions: [CoachArchetypeAliasSuggestion]? = nil,
        validation: CoachArchetypeValidation? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.archetypes = archetypes
        self.mapping = mapping
        self.variants = variants
        self.aliasSuggestions = aliasSuggestions
        self.validation = validation
    }

    public static let empty = CoachArchetypeCatalog(
        schemaVersion: "coach_archetype_catalog.v1",
        archetypes: [],
        mapping: [:],
        variants: [:]
    )
}

public struct CoachArchetype: Sendable, Hashable, Codable, Identifiable, Equatable {
    public let id: String
    public let displayName: String
    public let priority: String?
    public let coachAliases: [String]

    public init(
        id: String,
        displayName: String,
        priority: String? = nil,
        coachAliases: [String] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.priority = priority
        self.coachAliases = coachAliases
    }
}

public struct CoachArchetypeVariants: Sendable, Hashable, Codable, Equatable {
    public let members: [String]
    public let preferredDefaultExerciseId: String?

    public init(members: [String], preferredDefaultExerciseId: String? = nil) {
        self.members = members
        self.preferredDefaultExerciseId = preferredDefaultExerciseId
    }
}

public struct CoachArchetypeAliasSuggestion: Sendable, Hashable, Codable, Equatable {
    public let archetypeId: String
    public let suggestedAliases: [String]

    public init(archetypeId: String, suggestedAliases: [String]) {
        self.archetypeId = archetypeId
        self.suggestedAliases = suggestedAliases
    }
}

public struct CoachArchetypeValidation: Sendable, Hashable, Codable, Equatable {
    public let totalCatalogExercisesMapped: Int?
    public let unmappedCount: Int?
    public let mappingCoveragePercent: Int?
    public let cameronExercisesResolved: Int?
    public let cameronResolutionCoveragePercent: Int?
    public let totalArchetypes: Int?
}

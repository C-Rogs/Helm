import Core
import Foundation
import Persistence

public enum CoachArchetypeSupport: Sendable {
    nonisolated(unsafe) private(set) static var catalog: CoachArchetypeCatalog = .empty
    nonisolated(unsafe) private(set) static var archetypeByID: [String: CoachArchetype] = [:]
    nonisolated(unsafe) private(set) static var aliasToArchetypeID: [String: String] = [:]
    nonisolated(unsafe) private(set) static var exerciseToArchetypeID: [String: String] = [:]
    nonisolated(unsafe) private(set) static var exercisesByArchetypeID: [String: [String]] = [:]

    public static func configure(with catalog: CoachArchetypeCatalog) {
        self.catalog = catalog
        archetypeByID = Dictionary(uniqueKeysWithValues: catalog.archetypes.map { ($0.id, $0) })

        var aliases: [String: String] = [:]
        for archetype in catalog.archetypes {
            registerAlias(archetype.id, archetypeID: archetype.id, into: &aliases)
            registerAlias(archetype.displayName, archetypeID: archetype.id, into: &aliases)
            for coachAlias in archetype.coachAliases {
                registerAlias(coachAlias, archetypeID: archetype.id, into: &aliases)
            }
        }
        aliasToArchetypeID = aliases
        exerciseToArchetypeID = catalog.mapping

        var byArchetype: [String: [String]] = [:]
        for (exerciseID, archetypeID) in catalog.mapping {
            byArchetype[archetypeID, default: []].append(exerciseID)
        }
        for (archetypeID, variant) in catalog.variants {
            let merged = Set(byArchetype[archetypeID, default: []] + variant.members)
            byArchetype[archetypeID] = merged.sorted()
        }
        exercisesByArchetypeID = byArchetype
    }

    public static func archetype(for exerciseID: String) -> CoachArchetype? {
        guard let archetypeID = exerciseToArchetypeID[exerciseID] else { return nil }
        return archetypeByID[archetypeID]
    }

    public static func archetypeID(for phrase: String) -> String? {
        let candidates = ExerciseSearchNormalizer.searchCandidates(for: phrase)
        for candidate in candidates {
            if let archetypeID = aliasToArchetypeID[candidate] {
                return archetypeID
            }
        }
        let token = normalizeArchetypeToken(phrase)
        if let archetypeID = aliasToArchetypeID[token] {
            return archetypeID
        }
        if archetypeByID[token] != nil {
            return token
        }
        return nil
    }

    public static func preferredExerciseID(for archetypeID: String) -> String? {
        catalog.variants[archetypeID]?.preferredDefaultExerciseId
            ?? exercisesByArchetypeID[archetypeID]?.first
    }

    public static func memberExerciseIDs(for archetypeID: String) -> [String] {
        exercisesByArchetypeID[archetypeID] ?? []
    }

    public static func sessionArchetypeIDs(for exerciseIDs: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for exerciseID in exerciseIDs {
            guard let archetypeID = exerciseToArchetypeID[exerciseID],
                  seen.insert(archetypeID).inserted else { continue }
            ordered.append(archetypeID)
        }
        return ordered
    }

    private static func registerAlias(
        _ rawAlias: String,
        archetypeID: String,
        into aliases: inout [String: String]
    ) {
        for candidate in ExerciseSearchNormalizer.searchCandidates(for: rawAlias) {
            aliases[candidate] = archetypeID
        }
        aliases[normalizeArchetypeToken(rawAlias)] = archetypeID
    }

    private static func normalizeArchetypeToken(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }
}

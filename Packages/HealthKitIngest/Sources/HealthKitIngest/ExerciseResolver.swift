import Core
import Foundation
import Persistence

public enum ExerciseResolver {
    public struct Context: Sendable, Equatable {
        public let sessionExerciseIDs: Set<String>
        public let exerciseDisplayNames: [String: String]
        public let excludedExerciseIDs: Set<String>
        public let familiarExerciseIDs: Set<String>
        public let mustBeInSession: Bool

        public init(
            sessionExerciseIDs: Set<String>,
            exerciseDisplayNames: [String: String] = [:],
            excludedExerciseIDs: Set<String> = [],
            familiarExerciseIDs: Set<String> = [],
            mustBeInSession: Bool = false
        ) {
            self.sessionExerciseIDs = sessionExerciseIDs
            self.exerciseDisplayNames = exerciseDisplayNames
            self.excludedExerciseIDs = excludedExerciseIDs
            self.familiarExerciseIDs = familiarExerciseIDs
            self.mustBeInSession = mustBeInSession
        }
    }

    public struct Result: Sendable, Equatable {
        public let exerciseID: String?
        public let archetypeID: String?
        public let unresolvedPhrase: String?

        public init(exerciseID: String?, archetypeID: String? = nil, unresolvedPhrase: String? = nil) {
            self.exerciseID = exerciseID
            self.archetypeID = archetypeID
            self.unresolvedPhrase = unresolvedPhrase
        }
    }

    public static func resolve(
        _ rawPhrase: String?,
        context: Context,
        persistence: PersistenceStore
    ) -> Result {
        guard let rawPhrase, !rawPhrase.isEmpty else {
            return Result(exerciseID: rawPhrase)
        }

        if context.sessionExerciseIDs.contains(rawPhrase) {
            return Result(exerciseID: rawPhrase)
        }

        if let sessionMatch = sessionDisplayNameMatch(rawPhrase, context: context) {
            return Result(exerciseID: sessionMatch)
        }

        if let archetypeID = CoachArchetypeSupport.archetypeID(for: rawPhrase),
           let exerciseID = pickExercise(for: archetypeID, context: context) {
            return Result(exerciseID: exerciseID, archetypeID: archetypeID)
        }

        if CoachArchetypeSupport.exerciseToArchetypeID[rawPhrase] != nil,
           context.mustBeInSession == false {
            return Result(exerciseID: rawPhrase, archetypeID: CoachArchetypeSupport.exerciseToArchetypeID[rawPhrase])
        }

        if let resolved = try? persistence.exercises.resolveImportedTitle(rawPhrase)?.exerciseID,
           accepts(exerciseID: resolved, context: context) {
            return Result(
                exerciseID: resolved,
                archetypeID: CoachArchetypeSupport.exerciseToArchetypeID[resolved]
            )
        }

        let normalized = normalizeToken(rawPhrase)
        if let aliasMatch = try? persistence.exercises.resolveExerciseID(normalizedAlias: normalized),
           accepts(exerciseID: aliasMatch, context: context) {
            return Result(
                exerciseID: aliasMatch,
                archetypeID: CoachArchetypeSupport.exerciseToArchetypeID[aliasMatch]
            )
        }

        for sessionID in context.sessionExerciseIDs {
            if normalizeToken(sessionID) == normalized {
                return Result(exerciseID: sessionID)
            }
        }

        return Result(exerciseID: nil, unresolvedPhrase: rawPhrase)
    }

    private static func pickExercise(for archetypeID: String, context: Context) -> String? {
        let members = CoachArchetypeSupport.memberExerciseIDs(for: archetypeID)
        let preferred = CoachArchetypeSupport.preferredExerciseID(for: archetypeID)

        if let preferred, accepts(exerciseID: preferred, context: context) {
            return preferred
        }

        let ranked = members.sorted { lhs, rhs in
            score(exerciseID: lhs, context: context) > score(exerciseID: rhs, context: context)
        }
        return ranked.first { accepts(exerciseID: $0, context: context) }
    }

    private static func score(exerciseID: String, context: Context) -> Int {
        var value = 0
        if context.familiarExerciseIDs.contains(exerciseID) { value += 4 }
        if context.sessionExerciseIDs.contains(exerciseID) { value += 8 }
        if !context.excludedExerciseIDs.contains(exerciseID) { value += 2 }
        if exerciseID.hasPrefix("seed-") { value += 1 }
        return value
    }

    private static func accepts(exerciseID: String, context: Context) -> Bool {
        if context.excludedExerciseIDs.contains(exerciseID) {
            return false
        }
        if context.mustBeInSession, !context.sessionExerciseIDs.contains(exerciseID) {
            return false
        }
        return true
    }

    private static func sessionDisplayNameMatch(_ rawPhrase: String, context: Context) -> String? {
        let rawCandidates = Set(ExerciseSearchNormalizer.searchCandidates(for: rawPhrase))
        guard !rawCandidates.isEmpty else { return nil }

        for sessionID in context.sessionExerciseIDs {
            let label = ExerciseDisplayFormatter.friendlyName(
                for: sessionID,
                displayNames: context.exerciseDisplayNames
            )
            let labelCandidates = Set(ExerciseSearchNormalizer.searchCandidates(for: label))
            if !rawCandidates.isDisjoint(with: labelCandidates) {
                return sessionID
            }
        }
        return nil
    }

    private static func normalizeToken(_ value: String) -> String {
        var token = value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if token.hasPrefix("seed-") {
            token = String(token.dropFirst(5))
        }
        return token
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
    }
}

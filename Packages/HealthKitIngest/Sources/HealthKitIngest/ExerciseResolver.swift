import Core
import Foundation
import Persistence

public enum ExerciseResolver {
    public struct Context: Sendable, Equatable {
        public let sessionExerciseIDs: Set<String>
        public let exerciseDisplayNames: [String: String]
        public let excludedExerciseIDs: Set<String>
        public let familiarExerciseIDs: Set<String>
        public let recentExerciseIDs: Set<String>
        public let mustBeInSession: Bool
        /// Extra athlete wording (e.g. chat message) used to bias catalog / variant picks.
        public let phraseHint: String?

        public init(
            sessionExerciseIDs: Set<String>,
            exerciseDisplayNames: [String: String] = [:],
            excludedExerciseIDs: Set<String> = [],
            familiarExerciseIDs: Set<String> = [],
            recentExerciseIDs: Set<String> = [],
            mustBeInSession: Bool = false,
            phraseHint: String? = nil
        ) {
            self.sessionExerciseIDs = sessionExerciseIDs
            self.exerciseDisplayNames = exerciseDisplayNames
            self.excludedExerciseIDs = excludedExerciseIDs
            self.familiarExerciseIDs = familiarExerciseIDs
            self.recentExerciseIDs = recentExerciseIDs
            self.mustBeInSession = mustBeInSession
            self.phraseHint = phraseHint
        }
    }

    public struct Result: Sendable, Equatable {
        public let exerciseID: String?
        public let archetypeID: String?
        public let unresolvedPhrase: String?
        public let catalogCandidates: [String]

        public init(
            exerciseID: String?,
            archetypeID: String? = nil,
            unresolvedPhrase: String? = nil,
            catalogCandidates: [String] = []
        ) {
            self.exerciseID = exerciseID
            self.archetypeID = archetypeID
            self.unresolvedPhrase = unresolvedPhrase
            self.catalogCandidates = catalogCandidates
        }
    }

    private static let equipmentTokens: Set<String> = [
        "machine", "cable", "dumbbell", "db", "barbell", "bb", "rope", "smith", "band", "kettlebell", "kb",
    ]

    private static func equipmentTokens(in phrase: String) -> Set<String> {
        Set(phraseTokens(phrase).intersection(equipmentTokens))
    }

    private static func candidateMentionsEquipment(
        _ exerciseID: String,
        displayName: String,
        requested: Set<String>
    ) -> Bool {
        guard !requested.isEmpty else { return true }
        let haystack = phraseTokens(exerciseID + " " + displayName)
        for token in requested {
            if haystack.contains(where: { tokensMatch($0, token) }) {
                return true
            }
        }
        return false
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

        let searchPhrases = uniqueNonEmpty([context.phraseHint, rawPhrase])

        if context.mustBeInSession == false {
            // Athlete wording first (e.g. "rope hammer curl") so archetype IDs from the model
            // do not collapse to the preferred default variant.
            if let hint = context.phraseHint?.trimmingCharacters(in: .whitespacesAndNewlines),
               !hint.isEmpty {
                if let fuzzy = fuzzyCatalogMatch(hint, context: context, persistence: persistence) {
                    return catalogResult(exerciseID: fuzzy)
                }
                if let archetypeID = CoachArchetypeSupport.archetypeID(for: hint),
                   let exerciseID = pickExercise(
                    for: archetypeID,
                    context: context,
                    persistence: persistence,
                    phrase: hint
                   ) {
                    return Result(exerciseID: exerciseID, archetypeID: archetypeID)
                }
            }

            if let exact = exactAliasMatch(rawPhrase, context: context, persistence: persistence) {
                return catalogResult(exerciseID: exact)
            }

            if let archetypeID = CoachArchetypeSupport.archetypeID(for: rawPhrase),
               let exerciseID = pickExercise(
                for: archetypeID,
                context: context,
                persistence: persistence,
                phrase: context.phraseHint ?? rawPhrase
               ) {
                return Result(exerciseID: exerciseID, archetypeID: archetypeID)
            }

            if let fuzzy = fuzzyCatalogMatch(rawPhrase, context: context, persistence: persistence) {
                return catalogResult(exerciseID: fuzzy)
            }
        } else if let archetypeID = CoachArchetypeSupport.archetypeID(for: rawPhrase) {
            if let exerciseID = pickExercise(
                for: archetypeID,
                context: context,
                persistence: persistence,
                phrase: context.phraseHint ?? rawPhrase
            ) {
                return Result(exerciseID: exerciseID, archetypeID: archetypeID)
            }
            // Session may hold a catalog ID that maps to the archetype but was not in
            // the variants member list (or seed remap missed). Prefer any session hit.
            if context.mustBeInSession {
                for sessionID in context.sessionExerciseIDs {
                    let mapped = CoachArchetypeSupport.archetype(for: sessionID)?.id
                        ?? CoachArchetypeSupport.exerciseToArchetypeID[stripSeedPrefix(sessionID)]
                    if mapped == archetypeID {
                        return Result(exerciseID: sessionID, archetypeID: archetypeID)
                    }
                }
            }
        }

        // Nearby core IDs (chest_dip) miss in-session cousins (Bench Dip / triceps_dip).
        // Require the movement token (last word) so chest_dip cannot latch onto Bench Press.
        if context.mustBeInSession,
           let sessionMatch = sessionMovementOverlapMatch(rawPhrase, context: context) {
            return Result(
                exerciseID: sessionMatch,
                archetypeID: CoachArchetypeSupport.archetype(for: sessionMatch)?.id
                    ?? CoachArchetypeSupport.exerciseToArchetypeID[stripSeedPrefix(sessionMatch)]
            )
        }

        if context.mustBeInSession == false,
           let seeded = catalogExerciseID(rawPhrase, persistence: persistence),
           accepts(exerciseID: seeded, context: context) {
            return catalogResult(exerciseID: seeded)
        }

        for phrase in searchPhrases {
            if let resolved = try? persistence.exercises.resolveImportedTitle(phrase)?.exerciseID,
               accepts(exerciseID: resolved, context: context) {
                return catalogResult(exerciseID: resolved)
            }
        }

        let normalized = normalizeToken(rawPhrase)
        if let aliasMatch = try? persistence.exercises.resolveExerciseID(normalizedAlias: normalized),
           accepts(exerciseID: aliasMatch, context: context) {
            return catalogResult(exerciseID: aliasMatch)
        }

        for sessionID in context.sessionExerciseIDs {
            if normalizeToken(sessionID) == normalized {
                return Result(exerciseID: sessionID)
            }
        }

        let candidates = catalogCandidateLabels(
            for: context.phraseHint ?? rawPhrase,
            persistence: persistence
        )
        return Result(exerciseID: nil, unresolvedPhrase: rawPhrase, catalogCandidates: candidates)
    }

    private static func fuzzyCatalogMatch(
        _ rawPhrase: String,
        context: Context,
        persistence: PersistenceStore
    ) -> String? {
        let ranked = rankedCatalogMatches(for: rawPhrase, context: context, persistence: persistence)
        guard let best = ranked.first else { return nil }
        // Require meaningful token overlap so archetype IDs like "hammer_curl" do not
        // latch onto an arbitrary picker hit before seed-remapped archetype members run.
        guard best.overlap >= 2 || best.overlap == phraseTokens(rawPhrase).count else { return nil }
        let requested = equipmentTokens(in: rawPhrase)
        if !candidateMentionsEquipment(
            best.id,
            displayName: displayLabel(best.id, persistence: persistence),
            requested: requested
        ) {
            // Phrase names an equipment the candidate lacks (e.g. "hip thrust machine" vs
            // barbell row): refuse silent collapse so the caller surfaces candidates instead.
            return nil
        }
        return best.id
    }

    private static func exactAliasMatch(
        _ rawPhrase: String,
        context: Context,
        persistence: PersistenceStore
    ) -> String? {
        for candidate in ExerciseSearchNormalizer.searchCandidates(for: rawPhrase) {
            guard let exerciseID = try? persistence.exercises.resolveExerciseID(normalizedAlias: candidate),
                  accepts(exerciseID: exerciseID, context: context)
            else { continue }
            return exerciseID
        }
        return nil
    }

    private static func rankedCatalogMatches(
        for rawPhrase: String,
        context: Context,
        persistence: PersistenceStore
    ) -> [(id: String, overlap: Int, score: Int)] {
        let tokens = phraseTokens(rawPhrase)
        guard !tokens.isEmpty else { return [] }

        var scored: [(id: String, overlap: Int, score: Int)] = []
        var seen = Set<String>()

        if let summaries = try? persistence.exercises.listForPicker(search: rawPhrase, limit: 40) {
            for summary in summaries {
                guard seen.insert(summary.id).inserted,
                      accepts(exerciseID: summary.id, context: context) else { continue }
                let overlap = tokenOverlap(tokens, in: summary.id + " " + summary.displayName)
                let value = score(exerciseID: summary.id, context: context) + overlap * 10
                scored.append((summary.id, overlap, value))
            }
        }

        // Token OR search: multi-word athlete phrases often do not LIKE-match full titles.
        if tokens.count >= 2 {
            for token in tokens where token.count >= 3 {
                guard let summaries = try? persistence.exercises.listForPicker(search: token, limit: 40)
                else { continue }
                for summary in summaries {
                    guard seen.insert(summary.id).inserted,
                          accepts(exerciseID: summary.id, context: context) else { continue }
                    let overlap = tokenOverlap(tokens, in: summary.id + " " + summary.displayName)
                    let value = score(exerciseID: summary.id, context: context) + overlap * 10
                    scored.append((summary.id, overlap, value))
                }
            }
        }

        return scored.sorted { lhs, rhs in
            if lhs.overlap != rhs.overlap { return lhs.overlap > rhs.overlap }
            return lhs.score > rhs.score
        }
    }

    private static func catalogCandidateLabels(
        for rawPhrase: String,
        persistence: PersistenceStore
    ) -> [String] {
        let context = Context(sessionExerciseIDs: [], mustBeInSession: false)
        return rankedCatalogMatches(for: rawPhrase, context: context, persistence: persistence)
            .prefix(5)
            .compactMap { match in
                try? persistence.exercises.fetchSummary(id: match.id)?.displayName
            }
    }

    private static func pickExercise(
        for archetypeID: String,
        context: Context,
        persistence: PersistenceStore,
        phrase: String?
    ) -> String? {
        let members = CoachArchetypeSupport.memberExerciseIDs(for: archetypeID)
            .compactMap { catalogExerciseID($0, persistence: persistence) }
            .filter { accepts(exerciseID: $0, context: context) }

        guard !members.isEmpty else { return nil }

        let effectivePhrase = phrase ?? ""
        let tokens = phraseTokens(effectivePhrase)

        // Dead-alias guard: if the phrase carries equipment wording that no member shares
        // (e.g. "machine hip thrust" with a barbell-only archetype), the alias would silently
        // collapse to the default variant. Skip so resolution falls through to fuzzy/candidates.
        let requestedEquipment = equipmentTokens(in: effectivePhrase)
        if !requestedEquipment.isEmpty {
            let anyMemberMentions = members.contains { member in
                candidateMentionsEquipment(
                    member,
                    displayName: displayLabel(member, persistence: persistence),
                    requested: requestedEquipment
                )
            }
            if !anyMemberMentions {
                return nil
            }
        }

        let preferredRaw = CoachArchetypeSupport.preferredExerciseID(for: archetypeID)
        let preferred = preferredRaw.flatMap { catalogExerciseID($0, persistence: persistence) }
            .flatMap { accepts(exerciseID: $0, context: context) ? $0 : nil }

        // Prefer phrase-ranked members even when a preferred default exists, so equipment
        // wording (dumbbell vs rope) can beat the archetype default.
        if !tokens.isEmpty {
            let ranked = members.sorted { lhs, rhs in
                let leftOverlap = tokenOverlap(tokens, in: lhs + " " + displayLabel(lhs, persistence: persistence))
                let rightOverlap = tokenOverlap(tokens, in: rhs + " " + displayLabel(rhs, persistence: persistence))
                if leftOverlap != rightOverlap { return leftOverlap > rightOverlap }
                return score(exerciseID: lhs, context: context) > score(exerciseID: rhs, context: context)
            }
            if let best = ranked.first, tokenOverlap(tokens, in: best + " " + displayLabel(best, persistence: persistence)) > 0 {
                let preferredOverlap = preferred.map {
                    tokenOverlap(tokens, in: $0 + " " + displayLabel($0, persistence: persistence))
                } ?? 0
                if tokenOverlap(tokens, in: best + " " + displayLabel(best, persistence: persistence)) >= preferredOverlap {
                    return best
                }
            }
        }

        if let preferred {
            return preferred
        }

        return members.sorted { score(exerciseID: $0, context: context) > score(exerciseID: $1, context: context) }.first
    }

    private static func displayLabel(_ exerciseID: String, persistence: PersistenceStore) -> String {
        (try? persistence.exercises.fetchSummary(id: exerciseID)?.displayName) ?? exerciseID
    }

    private static func catalogExerciseID(_ rawID: String, persistence: PersistenceStore) -> String? {
        try? persistence.exercises.resolveSeededCatalogID(rawID)
    }

    private static func catalogResult(exerciseID: String) -> Result {
        Result(
            exerciseID: exerciseID,
            archetypeID: CoachArchetypeSupport.exerciseToArchetypeID[exerciseID]
                ?? CoachArchetypeSupport.exerciseToArchetypeID[stripSeedPrefix(exerciseID)]
        )
    }

    private static func score(exerciseID: String, context: Context) -> Int {
        var value = 0
        if context.familiarExerciseIDs.contains(exerciseID) { value += 4 }
        if context.recentExerciseIDs.contains(exerciseID) { value += 6 }
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

    /// Unique in-session exercise that shares the query's movement token (last word).
    /// `chest_dip` + session "Bench Dip" → match on `dip`; `chest_dip` + "Bench Press" → no.
    private static func sessionMovementOverlapMatch(_ rawPhrase: String, context: Context) -> String? {
        let queryTokens = phraseTokens(rawPhrase)
        guard !queryTokens.isEmpty, let movement = lastMovementToken(in: rawPhrase) else { return nil }

        var scored: [(id: String, overlap: Int)] = []
        for sessionID in context.sessionExerciseIDs {
            let label = ExerciseDisplayFormatter.friendlyName(
                for: sessionID,
                displayNames: context.exerciseDisplayNames
            )
            let haystack = sessionID + " " + label
            let haystackTokens = phraseTokens(haystack)
            guard haystackTokens.contains(where: { tokensMatch($0, movement) }) else { continue }
            let overlap = tokenOverlap(queryTokens, in: haystack)
            if overlap > 0 {
                scored.append((sessionID, overlap))
            }
        }

        guard let bestOverlap = scored.map(\.overlap).max() else { return nil }
        let winners = scored.filter { $0.overlap == bestOverlap }
        guard winners.count == 1 else { return nil }
        return winners[0].id
    }

    private static func lastMovementToken(in phrase: String) -> String? {
        let stop: Set<String> = [
            "a", "an", "the", "add", "in", "to", "please", "set", "of", "and", "or", "my", "me", "some"
        ]
        let ordered = ExerciseSearchNormalizer.normalize(phrase)
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count >= 2 && !stop.contains($0) }
        return ordered.last
    }

    private static func phraseTokens(_ value: String) -> Set<String> {
        let normalized = ExerciseSearchNormalizer.normalize(value)
        let stop: Set<String> = [
            "a", "an", "the", "add", "in", "to", "please", "set", "of", "and", "or", "my", "me", "some"
        ]
        return Set(
            normalized
                .split(separator: " ")
                .map(String.init)
                .filter { $0.count >= 2 && !stop.contains($0) }
        )
    }

    private static func tokenOverlap(_ tokens: Set<String>, in haystack: String) -> Int {
        let haystackTokens = phraseTokens(haystack)
        var count = 0
        for token in tokens {
            if haystackTokens.contains(where: { tokensMatch($0, token) }) {
                count += 1
            }
        }
        return count
    }

    private static func tokensMatch(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == rhs { return true }
        let shorter = lhs.count <= rhs.count ? lhs : rhs
        let longer = lhs.count <= rhs.count ? rhs : lhs
        guard shorter.count >= 3 else { return false }
        return longer.hasPrefix(shorter)
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

    private static func stripSeedPrefix(_ value: String) -> String {
        value.hasPrefix("seed-") ? String(value.dropFirst(5)) : value
    }

    private static func uniqueNonEmpty(_ values: [String?]) -> [String] {
        var seen = Set<String>()
        var results: [String] = []
        for value in values {
            guard let value else { continue }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { continue }
            results.append(trimmed)
        }
        return results
    }
}

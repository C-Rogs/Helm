import Foundation

public struct ResolvedNutrition: Sendable, Equatable {
    public let record: NutritionFoodRecord
    public let matchConfidence: MatchConfidence

    public enum MatchConfidence: Sendable, Equatable {
        case exact
        case synonym
        case partial
        case fallback
    }
}

/// On-device McCance & Widdowson CoFID lookup. No network.
public struct NutritionLookup: Sendable {
    private let records: [NutritionFoodRecord]
    private let normalizedIndex: [String: NutritionFoodRecord]
    private let fallbackRecord: NutritionFoodRecord

    public init() {
        self.init(bundle: Self.resourceBundle)
    }

    public init(bundle: Bundle) {
        let loaded = Self.loadRecords(from: bundle)
        records = loaded.records
        normalizedIndex = loaded.index
        fallbackRecord = loaded.fallback
    }

    init(records: [NutritionFoodRecord], fallback: NutritionFoodRecord) {
        self.records = records
        normalizedIndex = Self.buildIndex(records)
        fallbackRecord = fallback
    }

    public func resolve(item name: String) -> ResolvedNutrition? {
        let normalized = Self.normalize(name)
        guard !normalized.isEmpty else { return nil }

        if let record = normalizedIndex[normalized] {
            return ResolvedNutrition(record: record, matchConfidence: .exact)
        }

        if let record = records.first(where: { record in
            record.synonyms.contains { Self.normalize($0) == normalized }
        }) {
            return ResolvedNutrition(record: record, matchConfidence: .synonym)
        }

        let tokens = Set(normalized.split(separator: " ").map(String.init))
        var best: (record: NutritionFoodRecord, score: Int)?
        for record in records {
            let candidates = [record.description] + record.synonyms
            for candidate in candidates {
                let candidateTokens = Set(Self.normalize(candidate).split(separator: " ").map(String.init))
                let overlap = Self.tokenOverlapScore(queryTokens: tokens, candidateTokens: candidateTokens)
                let primaryWord = Self.primaryFoodToken(from: candidate)
                let boostedOverlap = primaryWord.map { primary in
                    tokens.contains(where: { Self.tokensEquivalent($0, primary) }) ? max(overlap, 2) : overlap
                } ?? overlap
                if boostedOverlap >= 2, boostedOverlap > (best?.score ?? 0) {
                    best = (record, boostedOverlap)
                }
            }
        }

        if let best {
            return ResolvedNutrition(record: best.record, matchConfidence: .partial)
        }

        if normalized.contains("oil") || normalized.contains("dressing") || normalized.contains("sauce") {
            if let oil = records.first(where: { $0.fdcId == "17-038" || $0.description.lowercased().contains("oil, olive") }) {
                return ResolvedNutrition(record: oil, matchConfidence: .fallback)
            }
        }

        return ResolvedNutrition(record: fallbackRecord, matchConfidence: .fallback)
    }

    /// Prefix/substring matches for inline food correction while editing photo meal line items.
    public func suggestionNames(matching query: String, limit: Int = 5) -> [String] {
        let normalized = Self.normalize(query)
        guard normalized.count >= 2 else { return [] }

        let queryTokens = Set(normalized.split(separator: " ").map(String.init))
        let processedModifiers = ["juice", "canned", "dried", "baked", "cooked", "stewed", "puree", "pureed", "frozen", "pickled", "sauce", "soup", "drink", "beverage", "concentrate"]
        let isSimpleQuery = queryTokens.count == 1

        var scored: [(name: String, score: Int)] = []
        for record in records {
            let description = Self.normalize(record.description)
            if description == normalized {
                scored.append((record.description, 200))
                continue
            }

            let primaryWord = description.split(separator: " ").first.map(String.init) ?? description
            if primaryWord == normalized || Self.tokensEquivalent(primaryWord, normalized) {
                scored.append((record.description, 180))
                continue
            }

            if Self.wordBoundaryMatch(description: description, query: normalized)
                || queryTokens.contains(where: { token in
                    description.split(separator: " ").contains(where: { Self.tokensEquivalent(token, String($0)) })
                }) {
                var score = 150
                if isSimpleQuery && processedModifiers.contains(where: { description.contains($0) }) {
                    score -= 80
                }
                scored.append((record.description, score))
                continue
            }

            if description.hasPrefix(normalized) {
                var score = 100
                if isSimpleQuery && processedModifiers.contains(where: { description.contains($0) }) {
                    score -= 50
                }
                scored.append((record.description, score))
                continue
            }

            if description.contains(normalized) {
                var score = 40
                if isSimpleQuery && processedModifiers.contains(where: { description.contains($0) }) {
                    score -= 30
                }
                scored.append((record.description, score))
                continue
            }

            if queryTokens.count >= 2 {
                let candidates = [record.description] + record.synonyms
                if candidates.contains(where: { candidate in
                    let normalizedCandidate = Self.normalize(candidate)
                    return queryTokens.allSatisfy { token in
                        normalizedCandidate.split(separator: " ").contains(where: { Self.tokensEquivalent(token, String($0)) })
                            || normalizedCandidate.contains(token)
                    }
                }) {
                    let normalizedDescription = Self.normalize(record.description)
                    let descriptionTokens = Set(normalizedDescription.split(separator: " ").map(String.init))
                    let overlap = Self.tokenOverlapScore(queryTokens: queryTokens, candidateTokens: descriptionTokens)
                    scored.append((record.description, 55 + overlap * 15))
                    continue
                }
            }

            for synonym in record.synonyms where Self.normalize(synonym).contains(normalized) {
                scored.append((record.description, 40))
                break
            }
        }

        var seen = Set<String>()
        return scored
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    if lhs.name.count == rhs.name.count {
                        return lhs.name < rhs.name
                    }
                    return lhs.name.count < rhs.name.count
                }
                return lhs.score > rhs.score
            }
            .compactMap { entry in
                let key = Self.normalize(entry.name)
                guard seen.insert(key).inserted else { return nil }
                return entry.name
            }
            .prefix(limit)
            .map { $0 }
    }

    private static func wordBoundaryMatch(description: String, query: String) -> Bool {
        let parts = description.split(separator: " ").map(String.init)
        for part in parts {
            let token = part.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            if tokensEquivalent(token, query) || token.hasPrefix(query) {
                return true
            }
        }
        return false
    }

    private static func primaryFoodToken(from candidate: String) -> String? {
        let head = candidate.split(separator: ",").first.map(String.init) ?? candidate
        let token = head.split(separator: " ").first.map(String.init) ?? head
        let normalized = normalize(token)
        return normalized.isEmpty ? nil : normalized
    }

    private static func tokenOverlapScore(queryTokens: Set<String>, candidateTokens: Set<String>) -> Int {
        var overlap = 0
        for query in queryTokens {
            for candidate in candidateTokens where tokensEquivalent(query, candidate) {
                overlap += 1
                break
            }
        }
        return overlap
    }

    static func tokensEquivalent(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == rhs { return true }
        if lhs == rhs + "s" || rhs == lhs + "s" { return true }
        if lhs.hasSuffix("es") && lhs.dropLast(2) == rhs { return true }
        if rhs.hasSuffix("es") && rhs.dropLast(2) == lhs { return true }
        if lhs.hasSuffix("ies") && lhs.dropLast(3) + "y" == rhs { return true }
        if rhs.hasSuffix("ies") && rhs.dropLast(3) + "y" == lhs { return true }
        return false
    }

    private static var resourceBundle: Bundle {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        return Bundle(for: NutritionLookupBundleToken.self)
        #endif
    }

    private static func loadRecords(from bundle: Bundle) -> (records: [NutritionFoodRecord], index: [String: NutritionFoodRecord], fallback: NutritionFoodRecord) {
        guard
            let url = bundle.url(forResource: "cofid_foods", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode(NutritionFoodBundle.self, from: data)
        else {
            let fallback = NutritionFoodRecord(
                fdcId: "generic_mixed",
                description: "Mixed dish",
                synonyms: ["mixed dish"],
                per100g: .init(kcal: 180, proteinG: 10, carbsG: 15, fatG: 9)
            )
            return ([fallback], ["mixed dish": fallback], fallback)
        }

        let fallback = decoded.foods.first { $0.fdcId == "generic_mixed" }
            ?? decoded.foods[0]
        return (decoded.foods, buildIndex(decoded.foods), fallback)
    }

    private static func buildIndex(_ records: [NutritionFoodRecord]) -> [String: NutritionFoodRecord] {
        var index: [String: NutritionFoodRecord] = [:]
        for record in records {
            index[normalize(record.description)] = record
            for synonym in record.synonyms {
                index[normalize(synonym)] = record
            }
        }
        return index
    }

    public static func normalize(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

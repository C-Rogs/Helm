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
        let normalized = Self.aliasedQuery(for: Self.normalize(name))
        guard !normalized.isEmpty else { return nil }

        if let record = normalizedIndex[normalized] {
            return ResolvedNutrition(record: record, matchConfidence: .exact)
        }

        if let record = records.first(where: { record in
            record.synonyms.contains { Self.normalize($0) == normalized }
        }) {
            return ResolvedNutrition(record: record, matchConfidence: .synonym)
        }

        let foodTokens = Self.foodTokens(from: normalized)
        guard !foodTokens.isEmpty else {
            return ResolvedNutrition(record: fallbackRecord, matchConfidence: .fallback)
        }

        var best: (record: NutritionFoodRecord, score: Int)?
        for record in records {
            let score = Self.matchScore(queryFoodTokens: foodTokens, recordDescription: record.description)
            guard score.overlap >= 1 else { continue }
            if best == nil || score.total > best!.score {
                best = (record, score.total)
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

    private struct MatchScore {
        let overlap: Int
        let total: Int
    }

    private static func matchScore(queryFoodTokens: Set<String>, recordDescription: String) -> MatchScore {
        let candidateFoodTokens = foodTokens(from: normalize(recordDescription))
        let overlap = tokenOverlapScore(queryTokens: queryFoodTokens, candidateTokens: candidateFoodTokens)
        let primary = primaryFoodToken(from: recordDescription)
        let primaryMatch = primary.map { p in
            queryFoodTokens.contains(where: { tokensEquivalent($0, p) })
        } ?? false
        let descriptionTokens = Set(normalize(recordDescription).split(separator: " ").map(String.init))
        let complexity = descriptionTokens.intersection(complexDishTokens).count
        let lengthPenalty = max(0, descriptionTokens.count - 5)
        let total = overlap * 10 + (primaryMatch ? 5 : 0) - complexity * 3 - lengthPenalty
        return MatchScore(overlap: overlap, total: total)
    }

    private static func foodTokens(from normalized: String) -> Set<String> {
        Set(
            normalized
                .split(separator: " ")
                .map(String.init)
                .filter { token in
                    token.count >= 3 && !modifierTokens.contains(token)
                }
        )
    }

    private static func aliasedQuery(for normalized: String) -> String {
        if let alias = phraseAliases[normalized] {
            return alias
        }
        if normalized.contains("napa") && normalized.contains("cabbage") {
            return "cabbage chinese raw"
        }
        if normalized.contains("fish") && normalized.contains("cooked") {
            return "cod flesh only grilled"
        }
        if normalized.contains("white fish") || normalized == "white fish" {
            return "cod flesh only grilled"
        }
        return normalized
    }

    private static let modifierTokens: Set<String> = [
        "raw", "cooked", "fried", "grilled", "baked", "boiled", "steamed", "roasted", "smoked",
        "fresh", "frozen", "canned", "dried", "drained", "sliced", "diced", "chopped", "minced", "grated",
        "average", "lean", "fat", "only", "flesh", "skin", "without", "with", "no", "not",
        "and", "the", "of", "in", "on", "a", "from", "type", "style",
        "large", "small", "medium", "whole", "half", "thin", "thick",
        "boneless", "skinless", "free", "range", "organic", "hass", "including", "excluding",
        "weighed", "approx", "meat", "portion", "pieces", "piece",
    ]

    private static let complexDishTokens: Set<String> = [
        "stuffed", "homemade", "retail", "pie", "cake", "fingers", "coated", "breadcrumbs",
        "curry", "sauce", "sandwich", "burger", "pizza", "croute", "crusted", "topped", "balls", "ball", "paste",
    ]

    private static let phraseAliases: [String: String] = [
        "napa cabbage": "cabbage chinese raw",
        "chinese cabbage": "cabbage chinese raw",
        "cooked fish meat": "cod flesh only grilled",
        "cooked fish": "cod flesh only grilled",
        "white fish": "cod flesh only grilled",
        "sliced cucumbers": "cucumber raw",
        "sliced cucumber": "cucumber raw",
        // Drink nicknames → searchable form. CoFID has no G&T row; emptying weak
        // single-token noise lets FoodResolver fall through to Open Food Facts.
        "g t": "gin tonic",
        "g and t": "gin tonic",
        "gt": "gin tonic",
    ]

    /// Prefix/substring matches for inline food correction while editing photo meal line items.
    public func suggestionNames(matching query: String, limit: Int = 5) -> [String] {
        let normalized = Self.aliasedQuery(for: Self.normalize(query))
        guard normalized.count >= 2 else { return [] }

        let rawTokens = normalized.split(separator: " ").map(String.init)
        // Drop stopwords ("and", "with") and 1-char noise ("g", "t" from G&T) so weak
        // token overlap cannot flood CoFID and block Open Food Facts.
        let significantTokens = Set(Self.significantSearchTokens(from: rawTokens))
        guard !significantTokens.isEmpty else { return [] }

        let processedModifiers = ["juice", "canned", "dried", "baked", "cooked", "stewed", "puree", "pureed", "frozen", "pickled", "sauce", "soup", "drink", "beverage", "concentrate"]
        let isMultiToken = significantTokens.count >= 2
        let isSimpleQuery = significantTokens.count == 1
        let simpleQuery = isSimpleQuery ? significantTokens.first! : normalized

        var scored: [(name: String, score: Int)] = []
        for record in records {
            let description = Self.normalize(record.description)
            if description == normalized {
                scored.append((record.description, 200))
                continue
            }

            let primaryWord = description.split(separator: " ").first.map(String.init) ?? description
            if primaryWord == normalized || Self.tokensEquivalent(primaryWord, normalized)
                || (isSimpleQuery && (primaryWord == simpleQuery || Self.tokensEquivalent(primaryWord, simpleQuery))) {
                scored.append((record.description, 180))
                continue
            }

            // Multi-token queries must match every significant token; never promote on
            // a shared stopword or single shared word (e.g. "and" / "tonic" alone).
            if isMultiToken {
                let candidates = [record.description] + record.synonyms
                if candidates.contains(where: { candidate in
                    let candidateTokens = Set(Self.normalize(candidate).split(separator: " ").map(String.init))
                    return Self.tokenOverlapScore(queryTokens: significantTokens, candidateTokens: candidateTokens)
                        == significantTokens.count
                }) {
                    let descriptionTokens = Set(description.split(separator: " ").map(String.init))
                    let overlap = Self.tokenOverlapScore(queryTokens: significantTokens, candidateTokens: descriptionTokens)
                    scored.append((record.description, 55 + overlap * 15))
                }
                continue
            }

            if Self.wordBoundaryMatch(description: description, query: simpleQuery)
                || description.split(separator: " ").contains(where: { Self.tokensEquivalent(simpleQuery, String($0)) }) {
                var score = 150
                if processedModifiers.contains(where: { description.contains($0) }) {
                    score -= 80
                }
                scored.append((record.description, score))
                continue
            }

            // Short tokens ("gin") must not substring-match "ginger" / "aubergine".
            guard simpleQuery.count >= 4 else { continue }

            if description.hasPrefix(simpleQuery) || description.hasPrefix(normalized) {
                var score = 100
                if processedModifiers.contains(where: { description.contains($0) }) {
                    score -= 50
                }
                scored.append((record.description, score))
                continue
            }

            if description.contains(simpleQuery) || description.contains(normalized) {
                var score = 40
                if processedModifiers.contains(where: { description.contains($0) }) {
                    score -= 30
                }
                scored.append((record.description, score))
                continue
            }

            for synonym in record.synonyms {
                let normalizedSynonym = Self.normalize(synonym)
                if normalizedSynonym.contains(simpleQuery) || normalizedSynonym.contains(normalized) {
                    scored.append((record.description, 40))
                    break
                }
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

    private static func significantSearchTokens(from tokens: [String]) -> [String] {
        tokens.filter { token in
            token.count >= 2 && !modifierTokens.contains(token)
        }
    }

    private static func wordBoundaryMatch(description: String, query: String) -> Bool {
        let parts = description.split(separator: " ").map(String.init)
        for part in parts {
            let token = part.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            // Require exact/plural equivalence for short queries so "gin" does not match "ginger".
            if tokensEquivalent(token, query) {
                return true
            }
            if query.count >= 4 && token.hasPrefix(query) {
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

    public static func tokensEquivalent(_ lhs: String, _ rhs: String) -> Bool {
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

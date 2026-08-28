import Foundation

/// Normalizes exercise titles for fuzzy picker search and import resolution.
public enum ExerciseSearchNormalizer {
    /// Lowercases, strips parenthetical equipment tags, collapses punctuation and whitespace.
    public static func normalize(_ text: String) -> String {
        normalize(text, keepEquipment: false)
    }

    /// Same as `normalize`, but keeps parenthetical equipment as extra tokens
    /// (`Hammer Curl (Cable)` → `hammer curl cable`) so variants do not collide.
    public static func normalizeKeepingEquipment(_ text: String) -> String {
        normalize(text, keepEquipment: true)
    }

    private static func normalize(_ text: String, keepEquipment: Bool) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let open = value.lastIndex(of: "("), value.hasSuffix(")") {
            let inside = String(value[value.index(after: open)..<value.index(before: value.endIndex)])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let stripped = String(value[..<open]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !stripped.isEmpty {
                value = keepEquipment && !inside.isEmpty ? "\(stripped) \(inside)" : stripped
            }
        }
        value = value
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        let tokens = value
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .map { synonym($0) }
        return tokens.joined(separator: " ")
    }

    /// Rope attachment is cable for search. db/bb stay as synonyms of dumbbell/barbell.
    public static func synonym(_ token: String) -> String {
        switch token {
        case "rope": "cable"
        case "db": "dumbbell"
        case "dumbbells": "dumbbell"
        case "bb": "barbell"
        case "barbells": "barbell"
        case "kb": "kettlebell"
        case "kettlebells": "kettlebell"
        case "cables": "cable"
        case "bands": "band"
        default: token
        }
    }

    /// Search variants: raw lowercased, normalized, and sorted-token form for word-order differences.
    public static func searchCandidates(for query: String) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var seen = Set<String>()
        var results: [String] = []

        func append(_ value: String) {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { return }
            results.append(normalized)
        }

        append(trimmed)
        append(normalize(trimmed))
        append(normalizeKeepingEquipment(trimmed))

        for source in [normalize(trimmed), normalizeKeepingEquipment(trimmed)] {
            let sortedTokens = source
                .split(separator: " ")
                .sorted()
                .joined(separator: " ")
            append(sortedTokens)
        }

        return results
    }
}

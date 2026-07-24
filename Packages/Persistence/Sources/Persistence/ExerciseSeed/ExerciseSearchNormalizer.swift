import Foundation

/// Normalizes exercise titles for fuzzy picker search and import resolution.
public enum ExerciseSearchNormalizer {
    /// Lowercases, strips parenthetical equipment tags, collapses punctuation and whitespace.
    public static func normalize(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let open = value.lastIndex(of: "("), value.hasSuffix(")") {
            let stripped = String(value[..<open]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !stripped.isEmpty {
                value = stripped
            }
        }
        value = value
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        let tokens = value
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        return tokens.joined(separator: " ")
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

        let sortedTokens = normalize(trimmed)
            .split(separator: " ")
            .sorted()
            .joined(separator: " ")
        append(sortedTokens)

        return results
    }
}

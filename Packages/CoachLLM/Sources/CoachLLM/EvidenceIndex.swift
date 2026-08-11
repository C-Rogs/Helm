import Core
import Foundation

/// Deterministic evidence-index serialization for the stable prefix.
public enum EvidenceIndex: Sendable {
    /// Flat alphabetical list (used by BriefPromptBuilder and legacy callers).
    public static func stableText(from records: [EvidenceRecord]) -> String {
        guard !records.isEmpty else { return "" }

        let lines = records
            .sorted { $0.id < $1.id }
            .map { record in
                var line = "- [\(record.id)] \(normalized(record.title)): \(normalized(record.summary))"
                let citation = normalized(record.citation)
                if !citation.isEmpty {
                    line += " (\(citation))"
                }
                if record.placeholder {
                    line += " [placeholder]"
                }
                return line
            }

        return lines.joined(separator: "\n")
    }

    /// Module-grouped list for easier domain-matching by the model.
    public static func groupedText(from grouped: [String: [EvidenceRecord]]) -> String {
        guard !grouped.isEmpty else { return "" }

        let sections = grouped.keys.sorted().compactMap { moduleTitle -> String? in
            guard let records = grouped[moduleTitle], !records.isEmpty else { return nil }
            let lines = records
                .sorted { $0.id < $1.id }
                .map { record in
                    var line = "- [\(record.id)] \(normalized(record.title)): \(normalized(record.summary))"
                    let citation = normalized(record.citation)
                    if !citation.isEmpty {
                        line += " (\(citation))"
                    }
                    if record.placeholder {
                        line += " [placeholder]"
                    }
                    return line
                }
            return "## \(moduleTitle)\n\(lines.joined(separator: "\n"))"
        }

        return sections.joined(separator: "\n\n")
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
}

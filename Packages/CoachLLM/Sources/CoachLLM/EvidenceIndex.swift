import Core
import Foundation

/// Deterministic evidence-index serialization for the stable prefix.
public enum EvidenceIndex: Sendable {
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

import Foundation

public enum CoachChatTextFormatter: Sendable {
    private static let structuredSchemas = Set(
        CoachOutputSchemaVersion.allCases.map(\.rawValue)
    )

    private static let evidenceRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"\[(ev-[a-z0-9-]+)\]"#)
    }()
    private static let topicRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"\[topic:([a-z0-9-]+)\]"#)
    }()
    private static let engineRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"\[engine:([a-z]+)\]"#)
    }()

    public static func userFacingText(from text: String) -> String {
        var result = text
        for block in CoachEmbeddedJSONBlockFinder.blocks(in: text) {
            let sanitized = CoachJSONSanitizer.sanitize(block)
            guard let data = sanitized.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let schemaVersion = object["schemaVersion"] as? String,
                  structuredSchemas.contains(schemaVersion)
            else {
                continue
            }
            result = result.replacingOccurrences(of: block, with: "")
        }

        result = result
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")

        return result
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n\n\n", with: "\n\n")
    }

    /// Detects cited evidence IDs and topic references embedded in coach responses.
    /// Pass an optional validation map to silently drop tags whose IDs were not
    /// present in the evidence index sent this turn.
    public static func sourceTags(from text: String, validation: CitationValidationMap? = nil) -> [CoachChatSourceTag] {
        var seen = Set<String>()
        var tags: [CoachChatSourceTag] = []
        var droppedEvidence: [String] = []
        var droppedTopic: [String] = []
        var droppedEngine: [String] = []

        let nsText = text as NSString
        let evidenceRange = NSRange(location: 0, length: nsText.length)
        evidenceRegex.enumerateMatches(in: text, range: evidenceRange) { match, _, _ in
            guard let matchRange = match?.range(at: 1), matchRange.location != NSNotFound else { return }
            let raw = nsText.substring(with: matchRange)
            guard seen.insert(raw).inserted else { return }
            if let v = validation, !v.isValidEvidence(raw) {
                droppedEvidence.append(raw)
                return
            }
            let title = ResourceModuleIndex.shared?.evidenceTitle(for: raw) ?? raw
            tags.append(CoachChatSourceTag(rawID: raw, display: title, kind: .evidence))
        }

        topicRegex.enumerateMatches(in: text, range: evidenceRange) { match, _, _ in
            guard let matchRange = match?.range(at: 1), matchRange.location != NSNotFound else { return }
            let raw = nsText.substring(with: matchRange)
            let id = "topic:\(raw)"
            guard seen.insert(id).inserted else { return }
            if let v = validation, !v.isValidTopic(id) {
                droppedTopic.append(raw)
                return
            }
            let title = ResourceModuleIndex.shared?.topicTitle(for: raw) ?? raw
            tags.append(CoachChatSourceTag(rawID: id, display: title, kind: .topic))
        }

        engineRegex.enumerateMatches(in: text, range: evidenceRange) { match, _, _ in
            guard let matchRange = match?.range(at: 1), matchRange.location != NSNotFound else { return }
            let raw = nsText.substring(with: matchRange)
            let id = "engine:\(raw)"
            guard seen.insert(id).inserted else { return }
            if let v = validation, !v.isValidEngine(raw) {
                droppedEngine.append(raw)
                return
            }
            let display = EngineAnchor(rawValue: raw)?.displayLabel ?? "Engine: \(raw)"
            tags.append(CoachChatSourceTag(rawID: id, display: display, kind: .engine))
        }

        if validation != nil {
            for raw in droppedEvidence {
                CoachCitationDiagnostics.logFailure(.phantomEvidence, rawTag: raw)
            }
            for raw in droppedTopic {
                CoachCitationDiagnostics.logFailure(.unknownTopic, rawTag: "topic:\(raw)")
            }
            for raw in droppedEngine {
                CoachCitationDiagnostics.logFailure(.unknownEngine, rawTag: "engine:\(raw)")
            }
        }

        return tags
    }
}

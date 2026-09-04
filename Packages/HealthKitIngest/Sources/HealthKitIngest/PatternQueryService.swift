import CoachLLM
import Foundation
import PatternKit
import Persistence

/// Stored PatternKit cards only. Coach narrates; this service never recomputes contrasts.
public struct PatternQueryService: Sendable {
    private let store: PersistenceStore

    public init(store: PersistenceStore) {
        self.store = store
    }

    public func run(_ payload: PatternQueryPayload) throws -> String {
        let wanted = statuses(for: payload.status)
        let findings = try PatternEvaluationService(store: store).storedFindings(statuses: wanted)
        let filtered = findings.filter { matches($0, field: payload.field) }
        let fieldToken = payload.field ?? "any"
        guard !filtered.isEmpty else {
            return "query=pattern status=\(payload.status.rawValue) field=\(fieldToken) count=0\nfindings=none"
        }
        var lines = [
            "query=pattern status=\(payload.status.rawValue) field=\(fieldToken) count=\(filtered.count)"
        ]
        for finding in filtered {
            lines.append("id=\(finding.id) status=\(finding.status.rawValue)")
            lines.append(finding.headline)
            lines.append(finding.body)
        }
        return lines.joined(separator: "\n")
    }

    private func statuses(for filter: PatternQueryPayload.StatusFilter) -> [FindingStatus]? {
        switch filter {
        case .all:
            [.stable, .emerging, .priorSeed, .memoryConfirmed]
        case .stable:
            [.stable]
        case .emerging:
            [.emerging]
        case .priorSeed:
            [.priorSeed]
        case .retired:
            [.retired]
        case .memoryConfirmed:
            [.memoryConfirmed]
        }
    }

    private func matches(_ finding: PatternFinding, field: String?) -> Bool {
        guard let field, !field.isEmpty else { return true }
        let needle = field.lowercased().replacingOccurrences(of: "-", with: "_")
        let exposure = finding.spec.exposure.field.rawValue
        let outcome = finding.spec.outcome.field.rawValue
        if exposure == needle || outcome == needle {
            return true
        }
        guard needle.count >= 4 else { return false }
        return exposure.hasPrefix(needle) || outcome.hasPrefix(needle)
    }
}

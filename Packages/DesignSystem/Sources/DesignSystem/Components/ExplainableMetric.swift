import Foundation

public struct ExplainContributor: Sendable, Hashable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public let value: String
    public let detail: String?
    public let state: HelmState?

    public init(
        id: String,
        label: String,
        value: String,
        detail: String? = nil,
        state: HelmState? = nil
    ) {
        self.id = id
        self.label = label
        self.value = value
        self.detail = detail
        self.state = state
    }
}

public struct ExplainCitation: Sendable, Hashable, Equatable {
    public let id: String
    public let label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}

public struct ExplainableMetric: Sendable, Hashable, Equatable {
    public let domain: String
    public let title: String
    public let value: String
    public let unit: String?
    public let state: HelmState?
    public let summary: String?
    public let contributors: [ExplainContributor]
    public let citation: ExplainCitation?
    public let coachPromptSeed: String
    public let isCoachHandoffEnabled: Bool

    public init(
        domain: String,
        title: String,
        value: String,
        unit: String? = nil,
        state: HelmState? = nil,
        summary: String? = nil,
        contributors: [ExplainContributor],
        citation: ExplainCitation? = nil,
        coachPromptSeed: String,
        isCoachHandoffEnabled: Bool
    ) {
        self.domain = domain
        self.title = title
        self.value = value
        self.unit = unit
        self.state = state
        self.summary = summary
        self.contributors = contributors
        self.citation = citation
        self.coachPromptSeed = coachPromptSeed
        self.isCoachHandoffEnabled = isCoachHandoffEnabled
    }

    public func disablingCoachHandoff() -> ExplainableMetric {
        ExplainableMetric(
            domain: domain,
            title: title,
            value: value,
            unit: unit,
            state: state,
            summary: summary,
            contributors: contributors,
            citation: citation,
            coachPromptSeed: coachPromptSeed,
            isCoachHandoffEnabled: false
        )
    }
}

public enum ExplainableMetricSnapshot {
    public static func text(for metric: ExplainableMetric) -> String {
        var lines: [String] = [
            "# \(metric.domain)",
            "## \(metric.title)",
            metric.value + (metric.unit.map { " \($0)" } ?? ""),
        ]

        if let state = metric.state {
            lines.append("state=\(state.rawValue)")
        }

        if let summary = metric.summary, !summary.isEmpty {
            lines.append("summary=\(summary)")
        }

        lines.append("## Contributors")
        if metric.contributors.isEmpty {
            lines.append("- none")
        } else {
            for contributor in metric.contributors {
                var row = "- \(contributor.label): \(contributor.value)"
                if let detail = contributor.detail, !detail.isEmpty {
                    row += " | \(detail)"
                }
                if let state = contributor.state {
                    row += " | state=\(state.rawValue)"
                }
                lines.append(row)
            }
        }

        lines.append("## Citation")
        if let citation = metric.citation {
            lines.append("\(citation.id) · \(citation.label)")
        } else {
            lines.append("none")
        }

        lines.append("## Coach hand-off")
        lines.append("enabled=\(metric.isCoachHandoffEnabled)")
        lines.append("prompt=\(metric.coachPromptSeed)")

        return lines.joined(separator: "\n")
    }
}

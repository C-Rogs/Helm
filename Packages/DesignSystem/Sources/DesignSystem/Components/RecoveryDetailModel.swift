import Foundation

public struct RecoveryContributorRow: Sendable, Hashable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public let value: Double
    public let band: ClosedRange<Double>?
    public let unit: String
    public let state: HelmState
    public let verdictTag: String?
    public let decimalPlaces: Int

    public init(
        id: String,
        label: String,
        value: Double,
        band: ClosedRange<Double>?,
        unit: String,
        state: HelmState,
        verdictTag: String? = nil,
        decimalPlaces: Int = 1
    ) {
        self.id = id
        self.label = label
        self.value = value
        self.band = band
        self.unit = unit
        self.state = state
        self.verdictTag = verdictTag
        self.decimalPlaces = decimalPlaces
    }
}

public struct RecoveryHistoryPoint: Sendable, Hashable, Equatable, Identifiable {
    public let dayLabel: String
    public let score: Int
    public let state: HelmState

    public var id: String { dayLabel }

    public init(dayLabel: String, score: Int, state: HelmState) {
        self.dayLabel = dayLabel
        self.score = score
        self.state = state
    }
}

public struct RecoveryDetailModel: Sendable, Hashable, Equatable {
    public let score: Int
    public let helmState: HelmState
    public let targetBand: ClosedRange<Double>
    public let narration: String
    public let isEngineOnly: Bool
    public let citationLabel: String?
    public let contributors: [RecoveryContributorRow]
    public let history: [RecoveryHistoryPoint]
    public let validNights: Int
    public let coachPrompt: String
    public let isCoachHandoffEnabled: Bool

    public init(
        score: Int,
        helmState: HelmState,
        targetBand: ClosedRange<Double>,
        narration: String,
        isEngineOnly: Bool,
        citationLabel: String?,
        contributors: [RecoveryContributorRow],
        history: [RecoveryHistoryPoint],
        validNights: Int,
        coachPrompt: String,
        isCoachHandoffEnabled: Bool
    ) {
        self.score = score
        self.helmState = helmState
        self.targetBand = targetBand
        self.narration = narration
        self.isEngineOnly = isEngineOnly
        self.citationLabel = citationLabel
        self.contributors = contributors
        self.history = history
        self.validNights = validNights
        self.coachPrompt = coachPrompt
        self.isCoachHandoffEnabled = isCoachHandoffEnabled
    }
}

public enum RecoveryDetailSnapshot {
    public static func text(for model: RecoveryDetailModel) -> String {
        var lines: [String] = [
            "# Recovery",
            "## ARC Score",
            "\(model.score)",
            "state=\(model.helmState.rawValue)",
            "targetBand=\(Int(model.targetBand.lowerBound))-\(Int(model.targetBand.upperBound))",
            "narration=\(model.narration)",
            "engineOnly=\(model.isEngineOnly)",
            "validNights=\(model.validNights)"
        ]

        if let citationLabel = model.citationLabel {
            lines.append("citation=\(citationLabel)")
        }

        lines.append("## Contributors")
        if model.contributors.isEmpty {
            lines.append("- none")
        } else {
            for contributor in model.contributors {
                var row = "- \(contributor.label): \(format(contributor.value, places: contributor.decimalPlaces)) \(contributor.unit)"
                if let band = contributor.band {
                    let lower = format(band.lowerBound, places: contributor.decimalPlaces)
                    let upper = format(band.upperBound, places: contributor.decimalPlaces)
                    row += " | band \(lower)-\(upper)"
                } else {
                    row += " | band=building"
                }
                if let verdict = contributor.verdictTag {
                    row += " | \(verdict)"
                }
                row += " | state=\(contributor.state.rawValue)"
                lines.append(row)
            }
        }

        lines.append("## History")
        if model.history.isEmpty {
            lines.append("- none")
        } else {
            for point in model.history {
                lines.append("- \(point.dayLabel): \(point.score) | state=\(point.state.rawValue)")
            }
        }

        lines.append("## Coach hand-off")
        lines.append("enabled=\(model.isCoachHandoffEnabled)")
        lines.append("prompt=\(model.coachPrompt)")

        return lines.joined(separator: "\n")
    }

    private static func format(_ value: Double, places: Int) -> String {
        String(format: "%.\(places)f", value)
    }
}

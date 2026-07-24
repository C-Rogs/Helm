import DesignSystem
import SwiftUI

@MainActor
@ViewBuilder
func chartHeader(title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
        Text(title)
            .helmType(.title)
        Text(subtitle)
            .helmType(.body, color: HelmColor.fgSecondary)
    }
}

@MainActor
func emptyChartCopy(_ message: String) -> some View {
    Text(message)
        .helmType(.body, color: HelmColor.fgMuted)
        .frame(maxWidth: .infinity, minHeight: HelmLayout.emptyChartMinHeight, alignment: .leading)
}

@MainActor
func insufficientChartCopy(_ message: String) -> some View {
    Text(message)
        .helmType(.body, color: HelmColor.fgSecondary)
        .frame(maxWidth: .infinity, minHeight: HelmLayout.emptyChartMinHeight, alignment: .leading)
}

enum TrendsChartCoverage {
    static func trendMessage(
        pointCount: Int,
        minimumForTrend: Int = 2,
        unit: String = "day"
    ) -> String? {
        guard pointCount > 0, pointCount < minimumForTrend else { return nil }
        let remaining = minimumForTrend - pointCount
        let plural = remaining == 1 ? unit : "\(unit)s"
        return "Log \(remaining) more \(plural) for a trend."
    }

    static func sessionMessage(pointCount: Int, minimum: Int = 3) -> String? {
        guard pointCount > 0, pointCount < minimum else { return nil }
        let remaining = minimum - pointCount
        let unit = remaining == 1 ? "session" : "sessions"
        return "Log \(remaining) more \(unit) to chart e1RM."
    }

    static func baselineMessage(validNights: Int, required: Int = 4) -> String? {
        guard validNights > 0, validNights < required else { return nil }
        return "Building baseline \(validNights)/\(required)."
    }
}

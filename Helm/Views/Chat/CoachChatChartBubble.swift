import Charts
import CoachLLM
import DesignSystem
import SwiftUI

struct CoachChatChartBubble: View {
    let payload: ChartPayload

    var body: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            Text(payload.title)
                .helmType(.label)

            Chart(payload.points) { point in
                BarMark(
                    x: .value("Label", point.label),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(HelmColor.accent.opacity(0.85))
            }
            .helmChartStyle()
            .frame(height: HelmChartStyle.standardHeight)
            .accessibilityLabel(accessibilityLabel)

            if let unit = payload.unit, !unit.isEmpty {
                Text(unit.uppercased())
                    .helmType(.monoTag, color: HelmColor.fgMuted)
            }
        }
        .padding(.horizontal, HelmSpacing.md)
        .padding(.vertical, HelmSpacing.sm)
        .background(HelmColor.surface, in: RoundedRectangle(cornerRadius: HelmRadius.md))
    }

    private var accessibilityLabel: String {
        let unit = payload.unit.map { " \($0)" } ?? ""
        let summary = payload.points
            .map { "\($0.label) \(Int($0.value.rounded()))\(unit)" }
            .joined(separator: ", ")
        return "\(payload.title): \(summary)"
    }
}

#Preview("Chat chart bubble") {
    CoachChatChartBubble(
        payload: ChartPayload(
            reply: "Weekly hard sets.",
            title: "Hard sets",
            unit: "sets",
            points: [
                .init(label: "Mon", value: 12),
                .init(label: "Tue", value: 8),
                .init(label: "Wed", value: 14)
            ]
        )
    )
    .padding()
    .helmTheme()
}

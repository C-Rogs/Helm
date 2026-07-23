import DesignSystem
import HealthKitIngest
import SwiftUI

struct ThresholdInsightCard: View {
    let insight: ThresholdInsight

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                Text("Threshold insight")
                    .helmType(.monoTag, color: HelmColor.fgMuted)

                Text(insight.message)
                    .helmType(.body, color: HelmColor.fg)

                Text(insight.metricLabel.uppercased())
                    .helmType(.monoTag, color: HelmColor.accent)
            }
        }
        .skinAccentStripe(HelmColor.accent.opacity(0.35))
    }
}

#Preview {
    ThresholdInsightCard(
        insight: ThresholdInsight(
            id: "hrv_above",
            metricLabel: "HRV",
            message: "HRV moved above baseline (z +1.2).",
            direction: .above
        )
    )
    .padding()
    .helmTheme()
}

import DesignSystem
import SwiftUI

struct EnergyBalanceChartCard: View {
    let gauges: [EnergyBalanceGauge]

    private let columns = [
        GridItem(.flexible(), spacing: HelmSpacing.sm),
        GridItem(.flexible(), spacing: HelmSpacing.sm),
        GridItem(.flexible(), spacing: HelmSpacing.sm),
    ]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                chartHeader(
                    title: "Energy balance",
                    subtitle: "Logged intake vs calorie target"
                )

                if gauges.isEmpty {
                    emptyChartCopy("Log nutrition to compare intake against your targets.")
                } else {
                    LazyVGrid(columns: columns, spacing: HelmSpacing.md) {
                        ForEach(gauges.suffix(6)) { gauge in
                            VStack(spacing: HelmSpacing.xs) {
                                ArcGauge(
                                    value: gauge.intakeKcal,
                                    range: 0 ... max(gauge.targetKcal * 1.25, gauge.intakeKcal),
                                    state: gauge.state
                                ) {
                                    VStack(spacing: HelmSpacing.xxs) {
                                        Text("\(Int(gauge.intakeKcal.rounded()))")
                                            .helmType(.number)
                                        Text("kcal")
                                            .helmType(.monoTag, color: HelmColor.fgMuted)
                                    }
                                }
                                .frame(maxWidth: 96)

                                Text(TrendsChartSupport.shortLabel(for: gauge.helmDay))
                                    .helmType(.monoTag, color: HelmColor.fgMuted)

                                Text("target \(Int(gauge.targetKcal.rounded()))")
                                    .helmType(.monoTag, color: HelmColor.fgMuted)
                            }
                        }
                    }
                }
            }
        }
    }
}

#Preview("Energy balance") {
    EnergyBalanceChartCard(gauges: TrendChartFixtures.energyBalance)
        .padding()
        .helmTheme()
}

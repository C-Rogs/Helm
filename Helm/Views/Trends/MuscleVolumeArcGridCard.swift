import DesignSystem
import PlanKit
import SwiftUI

struct MuscleVolumeArcGridCard: View {
    let gauges: [MuscleVolumeGauge]

    private let columns = [
        GridItem(.flexible(), spacing: HelmSpacing.sm),
        GridItem(.flexible(), spacing: HelmSpacing.sm),
    ]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                chartHeader(
                    title: "Weekly volume",
                    subtitle: "Hard sets vs MEV/MRV landmarks"
                )

                if gauges.isEmpty {
                    emptyChartCopy("Log training this week to see per-muscle volume.")
                } else {
                    LazyVGrid(columns: columns, spacing: HelmSpacing.md) {
                        ForEach(gauges) { gauge in
                            VStack(spacing: HelmSpacing.xs) {
                                ArcGauge(
                                    value: gauge.weeklySets,
                                    range: 0 ... Double(gauge.landmarks.mrv),
                                    state: gauge.state
                                ) {
                                    VStack(spacing: HelmSpacing.xxs) {
                                        Text(String(format: "%.0f", gauge.weeklySets))
                                            .helmType(.bigNumber)
                                        Text(gauge.state.label)
                                            .helmType(.monoTag, color: HelmColor.fgMuted)
                                    }
                                }
                                .frame(maxWidth: 120)

                                Text(TrendsChartSupport.muscleLabel(gauge.muscle))
                                    .helmType(.label)
                                    .lineLimit(1)

                                Text("MEV \(gauge.landmarks.mev) · MRV \(gauge.landmarks.mrv)")
                                    .helmType(.monoTag, color: HelmColor.fgMuted)
                            }
                        }
                    }
                }
            }
        }
    }
}

#Preview("Muscle volume") {
    MuscleVolumeArcGridCard(gauges: TrendChartFixtures.muscleVolume)
        .padding()
        .helmTheme()
}

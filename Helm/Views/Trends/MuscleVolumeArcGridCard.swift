import DesignSystem
import PlanKit
import SwiftUI

struct MuscleVolumeArcGridCard: View {
    let gauges: [MuscleVolumeGauge]

    private let columns = [
        GridItem(.flexible(), spacing: HelmSpacing.sm),
        GridItem(.flexible(), spacing: HelmSpacing.sm),
        GridItem(.flexible(), spacing: HelmSpacing.sm)
    ]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                chartHeader(
                    title: "Volume arcs",
                    subtitle: "Weekly hard sets vs MEV/MRV landmarks"
                )

                if gauges.isEmpty {
                    emptyChartCopy("Log training this week to see per-muscle volume.")
                } else {
                    LazyVGrid(columns: columns, spacing: HelmSpacing.md) {
                        ForEach(gauges) { gauge in
                            VStack(spacing: HelmSpacing.xs) {
                                ArcGauge(
                                    value: gauge.weeklySets,
                                    range: 0 ... max(Double(gauge.landmarks.mrv) * 1.15, gauge.weeklySets, 1),
                                    state: gauge.state
                                ) {
                                    VStack(spacing: HelmSpacing.xxs) {
                                        HelmNumericText(gauge.weeklySets, format: "%.0f")
                                            .helmType(.number, color: HelmColor.color(for: gauge.state))
                                        Text("sets")
                                            .helmType(.monoTag, color: HelmColor.fgMuted)
                                    }
                                }
                                .frame(maxWidth: HelmLayout.compactArcWidth)

                                Text(TrendsChartSupport.muscleLabel(gauge.muscle))
                                    .helmType(.monoTag, color: HelmColor.fgMuted)
                                    .lineLimit(1)

                                Text(
                                    "\(Int(gauge.weeklySets.rounded())) / \(gauge.landmarks.mev)-\(gauge.landmarks.mrv)"
                                )
                                .helmType(.monoTag, color: HelmColor.color(for: gauge.state))
                                .monospacedDigit()

                                Text(
                                    VolumeLandmarkStatus.resolve(
                                        sets: gauge.weeklySets,
                                        mev: gauge.landmarks.mev,
                                        mrv: gauge.landmarks.mrv
                                    ).label
                                )
                                .helmType(.monoTag, color: HelmColor.fgMuted)
                            }
                        }
                    }
                }
            }
        }
    }
}

#Preview("Muscle volume arc grid") {
    MuscleVolumeArcGridCard(gauges: TrendChartFixtures.muscleVolumeStates)
        .padding()
        .helmTheme()
}

#Preview("Muscle volume arc grid data sheet") {
    MuscleVolumeArcGridCard(gauges: TrendChartFixtures.muscleVolumeStates)
        .padding()
        .helmTheme()
        .environment(\.helmSkin, .dataSheet)
}

#Preview("Muscle volume arc grid empty") {
    MuscleVolumeArcGridCard(gauges: [])
        .padding()
        .helmTheme()
}

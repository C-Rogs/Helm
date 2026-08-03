import DesignSystem
import PlanKit
import SwiftUI

struct MuscleVolumeBarChartCard: View {
    let gauges: [MuscleVolumeGauge]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                chartHeader(
                    title: "Weekly volume",
                    subtitle: "Logged + scheduled hard sets vs MEV/MRV"
                )

                if gauges.isEmpty {
                    emptyChartCopy("Log training this week to see per-muscle volume.")
                } else {
                    VStack(spacing: HelmSpacing.md) {
                        ForEach(gauges) { gauge in
                            LandmarkVolumeBar(
                                label: TrendsChartSupport.muscleLabel(gauge.muscle),
                                weeklySets: gauge.weeklySets,
                                scheduledSets: gauge.scheduledSets,
                                mev: gauge.landmarks.mev,
                                mrv: gauge.landmarks.mrv,
                                state: gauge.state,
                                daysSinceTrained: gauge.daysSinceTrained,
                                showsRecency: true
                            )
                        }
                    }

                    Text("Solid = logged · Tint = scheduled · Band = MEV to MRV")
                        .helmType(.monoTag, color: HelmColor.fgMuted)
                }
            }
        }
    }
}

#Preview("Muscle volume bars") {
    MuscleVolumeBarChartCard(gauges: TrendChartFixtures.muscleVolume)
        .padding()
        .helmTheme()
}

#Preview("Muscle volume states") {
    ScrollView {
        MuscleVolumeBarChartCard(gauges: TrendChartFixtures.muscleVolumeStates)
            .padding()
    }
    .helmTheme()
}

#Preview("Muscle volume empty") {
    MuscleVolumeBarChartCard(gauges: [])
        .padding()
        .helmTheme()
}

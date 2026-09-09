import DesignSystem
import PlanKit
import SwiftUI

struct MuscleDistributionCard: View {
    let rows: [MuscleDistributionRow]

    private var maxSets: Double {
        rows.map(\.hardSets).max() ?? 1
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                chartHeader(
                    title: "Muscle distribution",
                    subtitle: "Hard sets and session-day frequency"
                )

                if rows.isEmpty {
                    emptyChartCopy("Log strength work to see which muscles drove the window.")
                } else {
                    VStack(spacing: HelmSpacing.md) {
                        ForEach(rows.prefix(8)) { row in
                            VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                                HStack {
                                    Text(TrendsChartSupport.muscleLabel(row.muscle))
                                        .helmType(.body)
                                    Spacer()
                                    Text(String(format: "%.0f sets", row.hardSets.rounded()))
                                        .helmType(.monoTag, color: HelmColor.fgMuted)
                                }

                                GeometryReader { geometry in
                                    ZStack(alignment: .leading) {
                                        Capsule()
                                            .fill(HelmColor.gaugeTrack)
                                        Capsule()
                                            .fill(HelmColor.accent.opacity(0.85))
                                            .frame(width: geometry.size.width * barFraction(for: row.hardSets))
                                    }
                                }
                                .frame(height: HelmLayout.progressTrackHeight)

                                Text("\(row.sessionDays) session \(row.sessionDays == 1 ? "day" : "days")")
                                    .helmType(.monoTag, color: HelmColor.fgMuted)
                            }
                        }
                    }
                }
            }
        }
    }

    private func barFraction(for sets: Double) -> CGFloat {
        guard maxSets > 0 else { return 0 }
        return CGFloat(min(sets / maxSets, 1.0))
    }
}

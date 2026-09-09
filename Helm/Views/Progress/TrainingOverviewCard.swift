import DesignSystem
import SwiftUI

struct TrainingOverviewCard: View {
    let overview: TrainingOverviewSnapshot

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                chartHeader(
                    title: "Training overview",
                    subtitle: "Sessions, sets, and volume in this window"
                )

                if overview.sessionCount == 0 {
                    emptyChartCopy("Log workouts to compare training load across time ranges.")
                } else {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: HelmSpacing.sm),
                            GridItem(.flexible(), spacing: HelmSpacing.sm),
                        ],
                        spacing: HelmSpacing.md
                    ) {
                        metricTile(
                            title: "Sessions",
                            value: "\(overview.sessionCount)",
                            detail: String(format: "%.1f / wk", overview.sessionsPerWeek),
                            comparison: ProgressAnalyticsMath.signedPercentLabel(
                                ProgressAnalyticsMath.percentChange(
                                    current: overview.sessionsPerWeek,
                                    prior: overview.priorSessionsPerWeek
                                )
                            )
                        )
                        metricTile(
                            title: "Hard sets",
                            value: "\(overview.totalSets)",
                            detail: "Signal + Apple Fitness",
                            comparison: ProgressAnalyticsMath.signedPercentLabel(
                                ProgressAnalyticsMath.percentChange(
                                    current: Double(overview.totalSets),
                                    prior: Double(overview.priorTotalSets)
                                )
                            )
                        )
                        metricTile(
                            title: "Volume",
                            value: formattedVolume(overview.totalVolumeKg),
                            detail: "\(overview.helmSessionCount) Signal sessions",
                            comparison: ProgressAnalyticsMath.signedPercentLabel(
                                ProgressAnalyticsMath.percentChange(
                                    current: overview.totalVolumeKg,
                                    prior: overview.priorTotalVolumeKg
                                )
                            )
                        )
                        if overview.totalDurationSeconds > 0 {
                            metricTile(
                                title: "Duration",
                                value: formattedDuration(overview.totalDurationSeconds),
                                detail: "Logged timed work",
                                comparison: nil
                            )
                        }
                    }
                }
            }
        }
    }

    private func metricTile(
        title: String,
        value: String,
        detail: String,
        comparison: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
            Text(title)
                .helmType(.monoTag, color: HelmColor.fgMuted)
            Text(value)
                .helmType(.title)
            Text(detail)
                .helmType(.body, color: HelmColor.fgSecondary)
            if let comparison {
                Text("vs prior \(comparison)")
                    .helmType(.monoTag, color: HelmColor.fgMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formattedVolume(_ kilograms: Double) -> String {
        if kilograms >= 1_000 {
            return String(format: "%.1fk kg", kilograms / 1_000)
        }
        return String(format: "%.0f kg", kilograms.rounded())
    }

    private func formattedDuration(_ seconds: Int) -> String {
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

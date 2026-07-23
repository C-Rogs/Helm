import Charts
import DesignSystem
import SwiftUI

struct ReadinessHistoryChartCard: View {
    let points: [ReadinessHistoryPoint]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                chartHeader(
                    title: "Readiness history",
                    subtitle: "ARC score over time"
                )

                if points.isEmpty {
                    emptyChartCopy("Readiness scores appear after your first full day of data.")
                } else {
                    Chart(points) { point in
                        AreaMark(
                            x: .value("Day", TrendsChartSupport.chartDate(for: point.helmDay)),
                            y: .value("Score", point.score)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    HelmColor.depleted.opacity(0.15),
                                    HelmColor.primed.opacity(0.2),
                                ],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )

                        LineMark(
                            x: .value("Day", TrendsChartSupport.chartDate(for: point.helmDay)),
                            y: .value("Score", point.score)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    HelmColor.depleted,
                                    HelmColor.compromised,
                                    HelmColor.ready,
                                    HelmColor.primed,
                                ],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .lineStyle(StrokeStyle(lineWidth: HelmChartStyle.lineWidth))

                        PointMark(
                            x: .value("Day", TrendsChartSupport.chartDate(for: point.helmDay)),
                            y: .value("Score", point.score)
                        )
                        .foregroundStyle(HelmColor.color(for: point.state))
                        .symbolSize(HelmChartStyle.pointSize * HelmChartStyle.pointSize)
                    }
                    .helmChartStyle()
                    .frame(height: 180)
                }
            }
        }
    }
}

#Preview("Readiness history") {
    ReadinessHistoryChartCard(points: TrendChartFixtures.readinessHistory)
        .padding()
        .helmTheme()
}

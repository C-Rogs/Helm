import Charts
import Core
import DesignSystem
import SwiftUI

struct TrendWeightChartCard: View {
    let points: [TrendWeightPoint]
    let targetWeightKg: Double?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                chartHeader(
                    title: "Trend weight",
                    subtitle: "Smoothed body mass vs target"
                )

                if points.isEmpty {
                    emptyChartCopy("Log body weight in Health to see your trend.")
                } else {
                    Chart {
                        if let targetWeightKg {
                            RuleMark(y: .value("Target", targetWeightKg))
                                .foregroundStyle(HelmColor.ready)
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        }

                        ForEach(points) { point in
                            LineMark(
                                x: .value("Day", TrendsChartSupport.chartDate(for: point.helmDay)),
                                y: .value("Weight", point.trendWeightKg)
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
                                y: .value("Weight", point.trendWeightKg)
                            )
                            .foregroundStyle(HelmColor.color(for: point.state))
                            .symbolSize(HelmChartStyle.pointSize * HelmChartStyle.pointSize)
                        }
                    }
                    .helmChartStyle()
                    .frame(height: 180)

                    if let targetWeightKg {
                        Text("Target \(String(format: "%.1f", targetWeightKg)) kg")
                            .helmType(.monoTag, color: HelmColor.fgMuted)
                    }
                }
            }
        }
    }
}

#Preview("Trend weight") {
    TrendWeightChartCard(
        points: TrendChartFixtures.trendWeight,
        targetWeightKg: TrendChartFixtures.targetWeightKg
    )
    .padding()
    .helmTheme()
}

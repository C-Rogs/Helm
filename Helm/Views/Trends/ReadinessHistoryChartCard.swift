import Charts
import DesignSystem
import SwiftUI

struct ReadinessHistoryChartCard: View {
    let points: [ReadinessHistoryPoint]
    var showsSparkline = false
    var baselineNights: Int?

    @State private var selectedDay: Date?

    private var latestState: HelmState {
        points.last?.state ?? .ready
    }

    private var sparklinePoints: [HelmSparklinePoint] {
        TrendsChartSupport.sparklinePoints(from: points) { point, index in
            HelmSparklinePoint(
                id: point.helmDay.id,
                index: index,
                value: Double(point.score),
                state: point.state
            )
        }
    }

    private var insufficientMessage: String? {
        if let baselineNights,
           let baseline = TrendsChartCoverage.baselineMessage(validNights: baselineNights) {
            return baseline
        }
        return TrendsChartCoverage.trendMessage(pointCount: points.count)
    }

    private var selectedLabel: String? {
        guard let selectedDay else { return nil }
        guard let point = points.first(where: {
            TrendsChartSupport.chartDate(for: $0.helmDay) == selectedDay
        }) else {
            return nil
        }
        return "\(point.score)"
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                chartHeader(
                    title: "Readiness history",
                    subtitle: "ARC score over time"
                )

                if showsSparkline {
                    HelmSparkline(points: sparklinePoints, latestState: latestState)
                }

                if points.isEmpty {
                    emptyChartCopy("Readiness scores appear after your first full day of data.")
                } else if let insufficientMessage {
                    insufficientChartCopy(insufficientMessage)
                } else {
                    chartBody
                }
            }
        }
    }

    private var chartBody: some View {
        Chart(points) { point in
            let day = TrendsChartSupport.chartDate(for: point.helmDay)

            AreaMark(
                x: .value("Day", day),
                y: .value("Score", point.score)
            )
            .foregroundStyle(HelmColor.color(for: point.state).opacity(0.18))

            LineMark(
                x: .value("Day", day),
                y: .value("Score", point.score)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(HelmColor.color(for: point.state))
            .lineStyle(StrokeStyle(lineWidth: HelmChartStyle.lineWidth))

            PointMark(
                x: .value("Day", day),
                y: .value("Score", point.score)
            )
            .foregroundStyle(HelmColor.color(for: point.state))
            .symbolSize(HelmChartStyle.pointSize * HelmChartStyle.pointSize)

            if let selectedDay {
                RuleMark(x: .value("Selected", selectedDay))
                    .foregroundStyle(HelmColor.fgMuted.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .helmChartStyle()
        .helmChartScrub(selection: $selectedDay)
        .chartOverlay { proxy in
            TrendsChartSupport.scrubCalloutOverlay(
                proxy: proxy,
                selectedX: selectedDay,
                label: selectedLabel
            )
        }
        .frame(height: HelmChartStyle.standardHeight)
    }
}

#Preview("Readiness history") {
    ReadinessHistoryChartCard(points: TrendChartFixtures.readinessHistory)
        .padding()
        .helmTheme()
}

#Preview("Readiness sparkline") {
    ReadinessHistoryChartCard(
        points: TrendChartFixtures.readinessHistory,
        showsSparkline: true
    )
    .padding()
    .helmTheme()
}

#Preview("Readiness insufficient") {
    ReadinessHistoryChartCard(
        points: Array(TrendChartFixtures.readinessHistory.prefix(1)),
        baselineNights: 2
    )
    .padding()
    .helmTheme()
}

#Preview("Readiness reduce motion scrub") {
    ReadinessHistoryChartCard(points: TrendChartFixtures.readinessHistory)
        .padding()
        .helmTheme()
        .environment(\.helmReduceMotion, true)
}

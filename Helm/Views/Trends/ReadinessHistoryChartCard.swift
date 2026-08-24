import Charts
import DesignSystem
import SwiftUI

struct ReadinessHistoryChartCard: View {
    let points: [ReadinessHistoryPoint]
    var showsSparkline = false
    var showsBandOverlay = false
    var baselineNights: Int?
    var title = "Readiness history"
    var subtitle = "ARC score over time"

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

    private var selectedScore: Int? {
        guard let selectedDay else { return nil }
        guard let point = points.first(where: {
            TrendsChartSupport.chartDate(for: $0.helmDay) == selectedDay
        }) else {
            return nil
        }
        return point.score
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                chartHeader(title: title, subtitle: subtitle)

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
        Chart {
            if showsBandOverlay {
                bandOverlayMarks
            }

            ForEach(points) { point in
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
            }

            if let selectedDay {
                RuleMark(x: .value("Selected", selectedDay))
                    .foregroundStyle(HelmColor.fgMuted)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartYScale(domain: 0 ... 100)
        .helmChartStyle()
        .helmChartScrub(selection: $selectedDay)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let selectedDay,
                   let selectedScore,
                   let plotFrame = proxy.plotFrame,
                   let xPosition = proxy.position(forX: selectedDay) {
                    let origin = geometry[plotFrame].origin
                    let x = origin.x + xPosition

                    HelmNumericText(selectedScore)
                        .helmType(.number)
                        .padding(.horizontal, HelmSpacing.xs)
                        .padding(.vertical, HelmSpacing.xxs)
                        .background(HelmColor.surfaceElevated, in: Capsule())
                        .overlay {
                            Capsule()
                                .stroke(HelmColor.hairline, lineWidth: 1)
                        }
                        .position(x: x, y: origin.y - HelmSpacing.sm)
                }
            }
            .allowsHitTesting(false)
        }
        .frame(height: HelmChartStyle.standardHeight)
    }

    @ChartContentBuilder
    private var bandOverlayMarks: some ChartContent {
        let start = chartStart
        let end = chartEnd

        RectangleMark(
            xStart: .value("Start", start),
            xEnd: .value("End", end),
            yStart: .value("Primed", 67),
            yEnd: .value("Top", 100)
        )
        .foregroundStyle(HelmColor.primed.opacity(0.08))

        RectangleMark(
            xStart: .value("Start", start),
            xEnd: .value("End", end),
            yStart: .value("Balanced", 34),
            yEnd: .value("BalancedTop", 66)
        )
        .foregroundStyle(HelmColor.ready.opacity(0.08))

        RectangleMark(
            xStart: .value("Start", start),
            xEnd: .value("End", end),
            yStart: .value("Bottom", 0),
            yEnd: .value("Depleted", 33)
        )
        .foregroundStyle(HelmColor.depleted.opacity(0.08))
    }

    private var chartStart: Date {
        guard let first = points.first else { return Date() }
        return TrendsChartSupport.chartDate(for: first.helmDay)
    }

    private var chartEnd: Date {
        guard let last = points.last else { return Date() }
        return TrendsChartSupport.chartDate(for: last.helmDay)
    }
}

#Preview("Readiness band overlay") {
    ReadinessHistoryChartCard(
        points: TrendChartFixtures.readinessHistory,
        showsBandOverlay: true,
        title: "Readiness history",
        subtitle: "ARC score with target bands"
    )
    .padding()
    .helmTheme()
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

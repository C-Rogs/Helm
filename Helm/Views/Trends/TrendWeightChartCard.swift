import Charts
import Core
import DesignSystem
import SwiftUI

enum TrendWeightChartMode {
    /// Full-range daily scale readings (Trends tab).
    case detail
    /// Smoothed trend with a tight Y-axis on recent readings (Dashboard).
    case dashboard
}

struct TrendWeightChartCard: View {
    let points: [TrendWeightPoint]
    let targetWeightKg: Double?
    var mode: TrendWeightChartMode = .detail
    var showsSparkline = false

    @State private var selectedDay: Date?

    private var latestState: HelmState {
        points.last?.state ?? .ready
    }

    private var chartTitle: String {
        switch mode {
        case .detail: "Body weight"
        case .dashboard: "Trend weight"
        }
    }

    private var chartSubtitle: String {
        switch mode {
        case .detail: "Daily scale readings vs target"
        case .dashboard: "Smoothed body mass vs target"
        }
    }

    private var interpolation: InterpolationMethod {
        switch mode {
        case .detail: .linear
        case .dashboard: .catmullRom
        }
    }

    private var focusedYDomain: ClosedRange<Double>? {
        guard mode == .dashboard else { return nil }
        let recent = Array(points.suffix(7))
        guard !recent.isEmpty else { return nil }

        var values = recent.map(\.trendWeightKg)
        if let targetWeightKg {
            values.append(targetWeightKg)
        }

        guard let minValue = values.min(), let maxValue = values.max() else { return nil }
        let span = max(maxValue - minValue, 0.5)
        let padding = max(span * 0.15, 0.2)
        return (minValue - padding)...(maxValue + padding)
    }

    private var sparklinePoints: [HelmSparklinePoint] {
        TrendsChartSupport.sparklinePoints(from: points) { point, index in
            HelmSparklinePoint(
                id: point.helmDay.id,
                index: index,
                value: point.trendWeightKg,
                state: point.state
            )
        }
    }

    private var insufficientMessage: String? {
        TrendsChartCoverage.trendMessage(pointCount: points.count)
    }

    private var selectedLabel: String? {
        guard let selectedDay else { return nil }
        guard let point = points.first(where: {
            TrendsChartSupport.chartDate(for: $0.helmDay) == selectedDay
        }) else {
            return nil
        }
        return String(format: "%.1f kg", point.trendWeightKg)
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                chartHeader(
                    title: chartTitle,
                    subtitle: chartSubtitle
                )

                if showsSparkline {
                    HelmSparkline(points: sparklinePoints, latestState: latestState)
                }

                if points.isEmpty {
                    emptyChartCopy("Log body weight in Health to see your trend.")
                } else if let insufficientMessage {
                    insufficientChartCopy(insufficientMessage)
                } else {
                    chartBody

                    if let targetWeightKg {
                        HStack(spacing: HelmSpacing.xxs) {
                            Text("Target")
                                .helmType(.monoTag, color: HelmColor.fgMuted)
                            HelmNumericText(targetWeightKg, format: "%.1f")
                                .helmType(.monoTag, color: HelmColor.fgMuted)
                            Text("kg")
                                .helmType(.monoTag, color: HelmColor.fgMuted)
                        }
                    }
                }
            }
        }
    }

    private var chartBody: some View {
        Chart {
            if let targetWeightKg {
                RuleMark(y: .value("Target", targetWeightKg))
                    .foregroundStyle(HelmColor.color(for: .ready))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }

            ForEach(points) { point in
                let day = TrendsChartSupport.chartDate(for: point.helmDay)

                LineMark(
                    x: .value("Day", day),
                    y: .value("Weight", point.trendWeightKg)
                )
                .interpolationMethod(interpolation)
                .foregroundStyle(HelmColor.color(for: point.state))
                .lineStyle(StrokeStyle(lineWidth: HelmChartStyle.lineWidth))

                PointMark(
                    x: .value("Day", day),
                    y: .value("Weight", point.trendWeightKg)
                )
                .foregroundStyle(HelmColor.color(for: point.state))
                .symbolSize(HelmChartStyle.pointSize * HelmChartStyle.pointSize)
            }

            if let selectedDay {
                RuleMark(x: .value("Selected", selectedDay))
                    .foregroundStyle(HelmColor.fgMuted.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .helmChartStyle()
        .modifier(TrendWeightYScaleModifier(domain: focusedYDomain))
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

private struct TrendWeightYScaleModifier: ViewModifier {
    let domain: ClosedRange<Double>?

    func body(content: Content) -> some View {
        if let domain {
            content.chartYScale(domain: domain)
        } else {
            content
        }
    }
}

#Preview("Body weight detail") {
    TrendWeightChartCard(
        points: TrendChartFixtures.bodyWeight,
        targetWeightKg: TrendChartFixtures.targetWeightKg
    )
    .padding()
    .helmTheme()
}

#Preview("Trend weight") {
    TrendWeightChartCard(
        points: TrendChartFixtures.trendWeight,
        targetWeightKg: TrendChartFixtures.targetWeightKg
    )
    .padding()
    .helmTheme()
}

#Preview("Trend weight sparkline") {
    TrendWeightChartCard(
        points: TrendChartFixtures.trendWeight,
        targetWeightKg: TrendChartFixtures.targetWeightKg,
        mode: .dashboard,
        showsSparkline: true
    )
    .padding()
    .helmTheme()
}

#Preview("Trend weight insufficient") {
    TrendWeightChartCard(
        points: Array(TrendChartFixtures.trendWeight.prefix(1)),
        targetWeightKg: TrendChartFixtures.targetWeightKg
    )
    .padding()
    .helmTheme()
}

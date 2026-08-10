import Charts
import Core
import DesignSystem
import SwiftUI

enum TrendWeightChartMode {
    /// Full Trends surface: raw scale + smooth overlay.
    case detail
    /// Dashboard at-a-glance: same series, tighter chrome.
    case dashboard
}

struct TrendWeightChartCard: View {
    /// Daily scale readings (noise visible as dots).
    let rawPoints: [TrendWeightPoint]
    /// EWMA-smoothed trend (line).
    let trendPoints: [TrendWeightPoint]
    let targetWeightKg: Double?
    var mode: TrendWeightChartMode = .detail
    var showsSparkline = false
    var showsWindowPicker = false
    var historyWindow: Binding<TrendsHistoryWindow>? = nil

    @State private var selectedDay: Date?

    private var latestState: HelmState {
        trendPoints.last?.state ?? rawPoints.last?.state ?? .ready
    }

    private var chartTitle: String {
        switch mode {
        case .detail: "Body weight"
        case .dashboard: "Trend weight"
        }
    }

    private var chartSubtitle: String {
        "Scale readings + smoothed trend"
    }

    /// Zoom Y to every plotted series so history never clips below the plot.
    private var focusedYDomain: ClosedRange<Double>? {
        let values = rawPoints.map(\.trendWeightKg) + trendPoints.map(\.trendWeightKg)
        return TrendsChartSupport.autoZoomYDomain(
            values: values,
            nearby: targetWeightKg,
            minimumSpan: 0.5,
            minimumPadding: 0.2,
            nearbySlack: 2.0
        )
    }

    private var sparklinePoints: [HelmSparklinePoint] {
        let source = trendPoints.isEmpty ? rawPoints : trendPoints
        return TrendsChartSupport.sparklinePoints(from: source) { point, index in
            HelmSparklinePoint(
                id: point.helmDay.id,
                index: index,
                value: point.trendWeightKg,
                state: point.state
            )
        }
    }

    private var hasSeries: Bool {
        !rawPoints.isEmpty || !trendPoints.isEmpty
    }

    private var primaryCount: Int {
        max(rawPoints.count, trendPoints.count)
    }

    private var insufficientMessage: String? {
        TrendsChartCoverage.trendMessage(pointCount: primaryCount)
    }

    private var selectedLabel: String? {
        guard let selectedDay else { return nil }
        let raw = rawPoints.first {
            TrendsChartSupport.chartDate(for: $0.helmDay) == selectedDay
        }
        let trend = trendPoints.first {
            TrendsChartSupport.chartDate(for: $0.helmDay) == selectedDay
        }
        switch (raw, trend) {
        case let (raw?, trend?):
            return String(format: "%.1f kg · trend %.1f", raw.trendWeightKg, trend.trendWeightKg)
        case let (raw?, nil):
            return String(format: "%.1f kg", raw.trendWeightKg)
        case let (nil, trend?):
            return String(format: "trend %.1f kg", trend.trendWeightKg)
        case (nil, nil):
            return nil
        }
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                HStack(alignment: .top, spacing: HelmSpacing.sm) {
                    chartHeader(
                        title: chartTitle,
                        subtitle: chartSubtitle
                    )
                    Spacer(minLength: 0)
                    if showsWindowPicker, let historyWindow {
                        windowPicker(historyWindow)
                    }
                }

                if showsSparkline {
                    HelmSparkline(points: sparklinePoints, latestState: latestState)
                }

                if !hasSeries {
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

    private func windowPicker(_ binding: Binding<TrendsHistoryWindow>) -> some View {
        HStack(spacing: HelmSpacing.xxs) {
            ForEach(TrendsHistoryWindow.allCases) { window in
                let selected = binding.wrappedValue == window
                Button {
                    binding.wrappedValue = window
                } label: {
                    Text(window.label)
                        .helmType(.monoTag, color: selected ? HelmColor.accent : HelmColor.fgMuted)
                        .padding(.horizontal, HelmSpacing.xs)
                        .padding(.vertical, HelmSpacing.xxs)
                        .background(
                            selected ? HelmColor.accent.opacity(0.12) : Color.clear,
                            in: Capsule()
                        )
                        .overlay(
                            Capsule()
                                .stroke(selected ? HelmColor.accent.opacity(0.35) : HelmColor.hairline, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
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

            ForEach(rawPoints) { point in
                let day = TrendsChartSupport.chartDate(for: point.helmDay)
                PointMark(
                    x: .value("Day", day),
                    y: .value("Scale", point.trendWeightKg)
                )
                .foregroundStyle(HelmColor.fgMuted.opacity(0.55))
                .symbolSize(HelmChartStyle.pointSize * HelmChartStyle.pointSize * 0.55)
            }

            ForEach(trendPoints) { point in
                let day = TrendsChartSupport.chartDate(for: point.helmDay)
                LineMark(
                    x: .value("Day", day),
                    y: .value("Trend", point.trendWeightKg)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(HelmColor.color(for: point.state))
                .lineStyle(StrokeStyle(lineWidth: HelmChartStyle.lineWidth))
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
            .clipped()
        }
        .frame(height: HelmChartStyle.standardHeight)
        .clipped()
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
        rawPoints: TrendChartFixtures.bodyWeight,
        trendPoints: TrendChartFixtures.trendWeight,
        targetWeightKg: TrendChartFixtures.targetWeightKg
    )
    .padding()
    .helmTheme()
}

#Preview("Trend weight") {
    TrendWeightChartCard(
        rawPoints: TrendChartFixtures.bodyWeight,
        trendPoints: TrendChartFixtures.trendWeight,
        targetWeightKg: TrendChartFixtures.targetWeightKg,
        mode: .dashboard,
        showsWindowPicker: true,
        historyWindow: .constant(.days90)
    )
    .padding()
    .helmTheme()
}

#Preview("Trend weight sparkline") {
    TrendWeightChartCard(
        rawPoints: TrendChartFixtures.bodyWeight,
        trendPoints: TrendChartFixtures.trendWeight,
        targetWeightKg: TrendChartFixtures.targetWeightKg,
        mode: .dashboard,
        showsSparkline: true
    )
    .padding()
    .helmTheme()
}

#Preview("Trend weight insufficient") {
    TrendWeightChartCard(
        rawPoints: Array(TrendChartFixtures.bodyWeight.prefix(1)),
        trendPoints: Array(TrendChartFixtures.trendWeight.prefix(1)),
        targetWeightKg: TrendChartFixtures.targetWeightKg
    )
    .padding()
    .helmTheme()
}

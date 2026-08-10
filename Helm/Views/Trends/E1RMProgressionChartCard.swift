import Charts
import DesignSystem
import SwiftUI

struct E1RMProgressionChartCard: View {
    let points: [E1RMProgressionPoint]
    let exerciseName: String
    let onPickExercise: () -> Void

    @State private var selectedSession: Date?

    private var insufficientMessage: String? {
        TrendsChartCoverage.sessionMessage(pointCount: points.count)
    }

    private var selectedLabel: String? {
        guard let selectedSession else { return nil }
        guard let point = points.first(where: { $0.achievedAt == selectedSession }) else {
            return nil
        }
        return String(format: "%.0f kg", point.e1RMKilograms)
    }

    private var focusedYDomain: ClosedRange<Double>? {
        TrendsChartSupport.autoZoomYDomain(
            values: points.map(\.e1RMKilograms),
            minimumSpan: 2.5,
            minimumPadding: 1.0,
            nearbySlack: 5.0
        )
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                HStack(alignment: .firstTextBaseline) {
                    chartHeader(
                        title: "e1RM progression",
                        subtitle: exerciseName
                    )
                    Spacer()
                    Button("Change lift", action: onPickExercise)
                        .buttonStyle(.helmSecondary)
                }

                if points.isEmpty {
                    emptyChartCopy("Complete working sets to chart estimated 1RM over time.")
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
            LineMark(
                x: .value("Session", point.achievedAt),
                y: .value("e1RM", point.e1RMKilograms)
            )
            .interpolationMethod(.linear)
            .foregroundStyle(HelmColor.color(for: .primed))
            .lineStyle(StrokeStyle(lineWidth: HelmChartStyle.lineWidth))

            PointMark(
                x: .value("Session", point.achievedAt),
                y: .value("e1RM", point.e1RMKilograms)
            )
            .foregroundStyle(HelmColor.color(for: .primed))
            .symbolSize(HelmChartStyle.pointSize * HelmChartStyle.pointSize)

            if let selectedSession {
                RuleMark(x: .value("Selected", selectedSession))
                    .foregroundStyle(HelmColor.fgMuted.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .helmChartStyle()
        .modifier(E1RMYScaleModifier(domain: focusedYDomain))
        .helmChartScrub(selection: $selectedSession)
        .chartOverlay { proxy in
            TrendsChartSupport.scrubCalloutOverlay(
                proxy: proxy,
                selectedX: selectedSession,
                label: selectedLabel
            )
        }
        .frame(height: HelmChartStyle.standardHeight)
    }
}

private struct E1RMYScaleModifier: ViewModifier {
    let domain: ClosedRange<Double>?

    func body(content: Content) -> some View {
        if let domain {
            content.chartYScale(domain: domain)
        } else {
            content
        }
    }
}

#Preview("e1RM progression") {
    E1RMProgressionChartCard(
        points: TrendChartFixtures.e1RMHistory,
        exerciseName: "Squat (Barbell)",
        onPickExercise: {}
    )
    .padding()
    .helmTheme()
}

#Preview("e1RM insufficient") {
    E1RMProgressionChartCard(
        points: Array(TrendChartFixtures.e1RMHistory.prefix(2)),
        exerciseName: "Squat (Barbell)",
        onPickExercise: {}
    )
    .padding()
    .helmTheme()
}

import Charts
import SwiftUI

public enum HelmChartStyle {
    public static let axisLabelFont = HelmTypography.caption
    public static let axisLabelColor = HelmColor.textTertiary
    public static let gridColor = HelmColor.chartGrid
    public static let lineColor = HelmColor.chartLine
    public static let areaFill = HelmColor.chartAreaFill
    public static let lineWidth: CGFloat = 2
    public static let pointSize: CGFloat = 6
    public static let plotInsets = EdgeInsets(
        top: HelmSpacing.sm,
        leading: HelmSpacing.xs,
        bottom: HelmSpacing.xs,
        trailing: HelmSpacing.sm
    )
}

public extension View {
    /// Applies Helm chart axis and grid styling to a Swift Charts view.
    func helmChartStyle() -> some View {
        self
            .chartXAxis {
                AxisMarks { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(HelmChartStyle.gridColor)
                    AxisValueLabel()
                        .font(HelmChartStyle.axisLabelFont)
                        .foregroundStyle(HelmChartStyle.axisLabelColor)
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(HelmChartStyle.gridColor)
                    AxisValueLabel()
                        .font(HelmChartStyle.axisLabelFont)
                        .foregroundStyle(HelmChartStyle.axisLabelColor)
                }
            }
            .chartPlotStyle { plot in
                plot.padding(HelmChartStyle.plotInsets)
            }
    }
}

#if DEBUG
private struct SampleTrend: Identifiable {
    let id = UUID()
    let day: Int
    let value: Double
}

#Preview("Chart style") {
    let samples = (0..<7).map { SampleTrend(day: $0, value: Double.random(in: 55...85)) }

    Chart(samples) { point in
        AreaMark(
            x: .value("Day", point.day),
            y: .value("Score", point.value)
        )
        .foregroundStyle(HelmChartStyle.areaFill)

        LineMark(
            x: .value("Day", point.day),
            y: .value("Score", point.value)
        )
        .foregroundStyle(HelmChartStyle.lineColor)
        .lineStyle(StrokeStyle(lineWidth: HelmChartStyle.lineWidth))
    }
    .helmChartStyle()
    .frame(height: 200)
    .padding()
    .background(HelmColor.surface, in: RoundedRectangle(cornerRadius: HelmRadius.md))
    .padding()
    .helmTheme()
}
#endif

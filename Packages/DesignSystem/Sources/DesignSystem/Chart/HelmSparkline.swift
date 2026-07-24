import Charts
import SwiftUI

public struct HelmSparklinePoint: Identifiable, Sendable, Hashable {
    public let id: String
    public let index: Int
    public let value: Double
    public let state: HelmState

    public init(id: String, index: Int, value: Double, state: HelmState) {
        self.id = id
        self.index = index
        self.value = value
        self.state = state
    }
}

public struct HelmSparkline: View {
    private let points: [HelmSparklinePoint]
    private let latestState: HelmState?

    @Environment(\.helmReduceMotion) private var reduceMotion

    public init(points: [HelmSparklinePoint], latestState: HelmState? = nil) {
        self.points = points
        self.latestState = latestState
    }

    private var lineState: HelmState {
        latestState ?? points.last?.state ?? .ready
    }

    public var body: some View {
        Group {
            if points.count < 2 {
                insufficientTrack
            } else {
                chart
            }
        }
        .frame(height: HelmSpacing.xs + 2)
        .accessibilityLabel("Seven day trend")
    }

    private var chart: some View {
        Chart(points) { point in
            LineMark(
                x: .value("Day", point.index),
                y: .value("Value", point.value)
            )
            .interpolationMethod(.linear)
            .foregroundStyle(HelmColor.color(for: lineState))
            .lineStyle(StrokeStyle(lineWidth: 1.5))

            PointMark(
                x: .value("Day", point.index),
                y: .value("Value", point.value)
            )
            .foregroundStyle(HelmColor.color(for: point.state))
            .symbolSize(HelmChartStyle.pointSize)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartPlotStyle { plot in
            plot.padding(.vertical, HelmSpacing.xxs)
        }
        .animation(
            reduceMotion ? nil : HelmMotion.animation(HelmMotion.quickAnimation, reduceMotion: false),
            value: points.map(\.value)
        )
    }

    private var insufficientTrack: some View {
        Capsule()
            .fill(HelmColor.gaugeTrack)
            .overlay {
                if points.isEmpty {
                    Text("No trend yet")
                        .helmType(.monoTag, color: HelmColor.fgMuted)
                }
            }
    }
}

#if DEBUG
#Preview("Sparkline") {
    let points = (0 ..< 7).map { offset in
        HelmSparklinePoint(
            id: "\(offset)",
            index: offset,
            value: 60 + Double(offset) * 2,
            state: HelmState.readiness(score: 60 + Double(offset) * 2)
        )
    }

    HelmSparkline(points: points)
        .padding()
        .helmTheme()
}

#Preview("Sparkline reduce motion") {
    let points = (0 ..< 7).map { offset in
        HelmSparklinePoint(
            id: "\(offset)",
            index: offset,
            value: 72 - Double(offset),
            state: .ready
        )
    }

    HelmSparkline(points: points)
        .padding()
        .helmTheme()
        .environment(\.helmReduceMotion, true)
}
#endif

import Charts
import Core
import DesignSystem
import SwiftUI

struct SessionHeartRateChartView: View {
    let samples: [SessionHeartRateSample]
    let markers: [SessionSetMarker]

    var body: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            Text("Heart rate")
                .helmType(.label)

            if samples.isEmpty {
                Text("No heart rate recorded for this session.")
                    .helmType(.body, color: HelmColor.fgMuted)
                    .frame(maxWidth: .infinity, minHeight: HelmLayout.emptyChartMinHeight, alignment: .leading)
            } else {
                chartBody
            }
        }
    }

    private var chartBody: some View {
        Chart {
            ForEach(samples) { sample in
                AreaMark(
                    x: .value("Time", sample.offsetSeconds),
                    y: .value("BPM", sample.bpm)
                )
                .foregroundStyle(HelmChartStyle.areaFill)

                LineMark(
                    x: .value("Time", sample.offsetSeconds),
                    y: .value("BPM", sample.bpm)
                )
                .foregroundStyle(HelmChartStyle.lineColor)
                .lineStyle(StrokeStyle(lineWidth: HelmChartStyle.lineWidth))
                .interpolationMethod(.catmullRom)
            }

            ForEach(markers) { marker in
                RuleMark(x: .value("Set", marker.offsetSeconds))
                    .foregroundStyle(HelmColor.fgMuted.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, alignment: .center) {
                        Text("S\(marker.setNumber)")
                            .helmType(.monoTag, color: HelmColor.fgMuted)
                    }
            }
        }
        .helmChartStyle()
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(HelmChartStyle.gridColor)
                AxisValueLabel {
                    if let seconds = value.as(Int.self) {
                        Text(formatOffset(seconds))
                            .helmFont(.monoTag)
                            .foregroundStyle(HelmChartStyle.axisLabelColor)
                    }
                }
            }
        }
        .frame(height: HelmChartStyle.standardHeight)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        guard let first = samples.first, let last = samples.last else {
            return "Heart rate chart"
        }
        return "Heart rate from \(first.bpm) to \(last.bpm) BPM across \(samples.count) samples"
    }

    private func formatOffset(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let rem = seconds % 60
        return String(format: "%d:%02d", minutes, rem)
    }
}

#Preview("HR chart with samples") {
    SessionHeartRateChartView(
        samples: [
            SessionHeartRateSample(offsetSeconds: 0, bpm: 110),
            SessionHeartRateSample(offsetSeconds: 60, bpm: 132),
            SessionHeartRateSample(offsetSeconds: 120, bpm: 148),
            SessionHeartRateSample(offsetSeconds: 180, bpm: 140)
        ],
        markers: [
            SessionSetMarker(offsetSeconds: 60, setNumber: 1),
            SessionSetMarker(offsetSeconds: 180, setNumber: 2)
        ]
    )
    .padding()
    .helmTheme()
}

#Preview("HR chart empty") {
    SessionHeartRateChartView(samples: [], markers: [])
        .padding()
        .helmTheme()
}

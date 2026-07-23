import Charts
import DesignSystem
import SwiftUI

struct E1RMProgressionChartCard: View {
    let points: [E1RMProgressionPoint]
    let exerciseName: String
    let onPickExercise: () -> Void

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
                } else {
                    Chart(points) { point in
                        LineMark(
                            x: .value("Session", point.achievedAt),
                            y: .value("e1RM", point.e1RMKilograms)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
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
                            x: .value("Session", point.achievedAt),
                            y: .value("e1RM", point.e1RMKilograms)
                        )
                        .foregroundStyle(HelmColor.primed)
                        .symbolSize(HelmChartStyle.pointSize * HelmChartStyle.pointSize)
                    }
                    .helmChartStyle()
                    .frame(height: 180)
                }
            }
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

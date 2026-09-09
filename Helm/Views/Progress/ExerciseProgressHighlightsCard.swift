import DesignSystem
import SwiftUI

struct ExerciseProgressHighlightsCard: View {
    let rows: [ExerciseProgressRowModel]
    var onSelectExercise: ((String) -> Void)?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                chartHeader(
                    title: "Exercise highlights",
                    subtitle: "Best window result with prior-period delta"
                )

                if rows.isEmpty {
                    emptyChartCopy("Complete working sets to surface lift, bodyweight, timed, and cardio progress.")
                } else {
                    VStack(spacing: HelmSpacing.sm) {
                        ForEach(rows) { row in
                            Button {
                                onSelectExercise?(row.exerciseID)
                            } label: {
                                HStack(alignment: .firstTextBaseline, spacing: HelmSpacing.sm) {
                                    VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                                        Text(row.displayName)
                                            .helmType(.body)
                                        Text("\(row.sessionCount) sessions · \(row.metricKind.unitLabel)")
                                            .helmType(.monoTag, color: HelmColor.fgMuted)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: HelmSpacing.xxs) {
                                        Text(row.latestLabel)
                                            .helmType(.body)
                                        if let delta = row.deltaLabel {
                                            Text(delta)
                                                .helmType(.monoTag, color: row.deltaIsPositive ? HelmColor.ready : HelmColor.depleted)
                                        }
                                    }
                                }
                                .padding(.vertical, HelmSpacing.xxs)
                            }
                            .buttonStyle(.plain)
                            .disabled(onSelectExercise == nil)
                        }
                    }
                }
            }
        }
    }
}

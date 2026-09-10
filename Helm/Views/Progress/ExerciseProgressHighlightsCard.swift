import DesignSystem
import SwiftUI

struct ExerciseProgressHighlightsCard: View {
    let rows: [ExerciseProgressRowModel]
    var onOpenDetailedTrends: ((String) -> Void)?

    @State private var expandedExerciseID: String?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                chartHeader(
                    title: "Exercise highlights",
                    subtitle: "Tap an exercise to see what its result means"
                )

                if rows.isEmpty {
                    emptyChartCopy("Complete working sets to surface lift, bodyweight, timed, and cardio progress.")
                } else {
                    VStack(spacing: HelmSpacing.sm) {
                        ForEach(rows) { row in
                            VStack(alignment: .leading, spacing: HelmSpacing.xs) {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        expandedExerciseID = expandedExerciseID == row.exerciseID
                                            ? nil
                                            : row.exerciseID
                                    }
                                } label: {
                                    exerciseRow(row, isExpanded: expandedExerciseID == row.exerciseID)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(
                                    "\(row.displayName), \(row.metricKind.unitLabel), \(row.latestLabel)"
                                )
                                .accessibilityHint(
                                    expandedExerciseID == row.exerciseID
                                        ? "Double tap to hide exercise detail"
                                        : "Double tap to show exercise detail"
                                )

                                if expandedExerciseID == row.exerciseID {
                                    exerciseDetail(row)
                                        .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            }

                            if row.id != rows.last?.id {
                                Divider()
                                    .overlay(HelmColor.hairline)
                            }
                        }
                    }
                }
            }
        }
    }

    private func exerciseRow(
        _ row: ExerciseProgressRowModel,
        isExpanded: Bool
    ) -> some View {
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
                        .helmType(
                            .monoTag,
                            color: row.deltaIsPositive ? HelmColor.ready : HelmColor.depleted
                        )
                }
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(HelmColor.fgMuted)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .accessibilityHidden(true)
        }
        .padding(.vertical, HelmSpacing.xxs)
        .padding(.horizontal, HelmSpacing.xs)
        .background(
            isExpanded ? HelmColor.accent.opacity(0.08) : .clear,
            in: RoundedRectangle(cornerRadius: HelmRadius.sm)
        )
    }

    private func exerciseDetail(_ row: ExerciseProgressRowModel) -> some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("Exercise detail")
                    .helmType(.monoTag, color: HelmColor.fgMuted)
                Spacer()
                Text(row.displayName)
                    .helmType(.monoTag, color: HelmColor.accent)
                    .lineLimit(1)
            }

            HStack(spacing: HelmSpacing.sm) {
                detailMetric(label: "LATEST", value: row.latestLabel)
                detailMetric(label: "TRACKED AS", value: row.metricKind.unitLabel)
                detailMetric(label: "SESSIONS", value: "\(row.sessionCount)")
            }

            Text("This panel is the progress summary for \(row.displayName). Recomp and Scale are separate body trend views.")
                .helmType(.body, color: HelmColor.fgSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let onOpenDetailedTrends {
                Button {
                    onOpenDetailedTrends(row.exerciseID)
                } label: {
                    HStack {
                        Text("Open \(row.displayName) history in Trends")
                        Spacer()
                        HelmIconView(.chevronRight, context: .inline)
                    }
                }
                .buttonStyle(.helmSecondary)
                .accessibilityHint("Changes only the exercise history chart in Trends")
            }
        }
        .padding(HelmSpacing.sm)
        .background(HelmColor.surfaceElevated, in: RoundedRectangle(cornerRadius: HelmRadius.md))
        .accessibilityElement(children: .contain)
    }

    private func detailMetric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
            Text(label)
                .helmType(.monoTag, color: HelmColor.fgMuted)
            Text(value)
                .helmType(.body)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

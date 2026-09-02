import DesignSystem
import SwiftUI

struct ExerciseHistorySheet: View {
    let model: ExerciseHistoryModel
    var imageURL: URL? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HelmSpacing.lg) {
                    if let imageURL {
                        ExerciseImageView(
                            url: imageURL,
                            fallbackLabel: model.exerciseName
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: HelmLayout.exerciseHistoryImageHeight)
                        .accessibilityLabel("\(model.exerciseName) demonstration")
                    }

                    if let currentE1RM = model.currentE1RMKilograms {
                        Card {
                            VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                                Text("Current e1RM")
                                    .helmType(.monoTag, color: HelmColor.fgMuted)
                                HelmNumericText(currentE1RM, format: "%.0f kg")
                                    .helmType(.bigNumber, color: HelmColor.accent)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    previousSection
                    e1rmHistorySection
                }
                .padding(HelmSpacing.md)
            }
            .helmScreenBackground()
            .navigationTitle(model.exerciseName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var previousSection: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            Text("PREV")
                .helmType(.label)

            Card {
                if model.previousSets.isEmpty || model.previousSets.allSatisfy({ $0.previousLabel == nil }) {
                    emptyState("No previous sets logged.")
                } else {
                    VStack(spacing: 0) {
                        ForEach(model.previousSets) { row in
                            HelmRuledRow {
                                HStack(alignment: .center, spacing: HelmSpacing.sm) {
                                    Text(row.setTypeLabel == "\(row.setNumber)" ? "\(row.setNumber)" : row.setTypeLabel)
                                        .helmType(.monoTag, color: HelmColor.fgMuted)
                                        .frame(width: 22, alignment: .leading)
                                        .accessibilityLabel("Set \(row.setNumber), \(row.setTypeLabel)")

                                    Text(row.previousLabel ?? "-")
                                        .helmType(.number, color: row.previousLabel == nil ? HelmColor.fgMuted : HelmColor.fg)
                                        .helmNumericRoll(value: row.previousLabel ?? "-")
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    Text(row.sessionLabel ?? "")
                                        .helmType(.monoTag, color: HelmColor.fgMuted)
                                        .frame(width: 56, alignment: .trailing)
                                        .opacity(row.sessionLabel == nil ? 0 : 1)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var e1rmHistorySection: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            Text("e1RM history")
                .helmType(.label)

            Card {
                if model.e1RMHistory.isEmpty {
                    emptyState("Complete working sets to chart e1RM.")
                } else {
                    VStack(spacing: 0) {
                        ForEach(model.e1RMHistory) { row in
                            HelmRuledRow {
                                HStack(alignment: .center, spacing: HelmSpacing.sm) {
                                    Text(row.sessionLabel)
                                        .helmType(.body, color: HelmColor.fg)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    HelmNumericText(row.e1RMKilograms, format: "%.0f kg")
                                        .helmType(.number, color: HelmColor.accent)
                                        .frame(width: 72, alignment: .trailing)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .helmType(.body, color: HelmColor.fgSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(HelmSpacing.sm)
    }
}

#Preview("Exercise history") {
    ExerciseHistorySheet(model: .benchFixture)
        .helmTheme()
}

#Preview("Exercise history cold start") {
    ExerciseHistorySheet(model: .coldStartFixture)
        .helmTheme()
}

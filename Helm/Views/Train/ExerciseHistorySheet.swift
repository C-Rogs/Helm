import DesignSystem
import SwiftUI

struct ExerciseHistorySheet: View {
    let model: ExerciseHistoryModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HelmSpacing.lg) {
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
                                HStack(alignment: .firstTextBaseline, spacing: HelmSpacing.sm) {
                                    VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                                        Text("Set \(row.setNumber)")
                                            .helmType(.label)
                                        Text(row.setTypeLabel)
                                            .helmType(.monoTag, color: HelmColor.fgMuted)
                                    }
                                    .frame(width: 72, alignment: .leading)

                                    if let previousLabel = row.previousLabel {
                                        Text(previousLabel)
                                            .helmType(.body, color: HelmColor.fg)
                                            .helmNumericRoll(value: previousLabel)
                                    } else {
                                        Text("-")
                                            .helmType(.body, color: HelmColor.fgMuted)
                                    }

                                    Spacer(minLength: 0)

                                    if let sessionLabel = row.sessionLabel {
                                        Text(sessionLabel)
                                            .helmType(.monoTag, color: HelmColor.fgMuted)
                                    }
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
                                HStack {
                                    Text(row.sessionLabel)
                                        .helmType(.body, color: HelmColor.fg)
                                    Spacer()
                                    HelmNumericText(row.e1RMKilograms, format: "%.0f kg")
                                        .helmType(.monoTag, color: HelmColor.accent)
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

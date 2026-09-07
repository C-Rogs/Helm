import DesignSystem
import SwiftUI

struct ExerciseHistorySheet: View {
    enum Pane: String, CaseIterable, Identifiable {
        case form
        case history

        var id: String { rawValue }

        var title: String {
            switch self {
            case .form: "FORM"
            case .history: "HISTORY"
            }
        }
    }

    let model: ExerciseHistoryModel

    @Environment(\.dismiss) private var dismiss
    @State private var pane: Pane = .form

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                panePicker
                    .padding(.horizontal, HelmSpacing.md)
                    .padding(.top, HelmSpacing.sm)
                    .padding(.bottom, HelmSpacing.xs)

                ScrollView {
                    Group {
                        switch pane {
                        case .form:
                            formSection
                        case .history:
                            historySection
                        }
                    }
                    .padding(HelmSpacing.md)
                }
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
        .onAppear {
            HapticEngine.shared.play(.selection)
            if !model.hasFormContent {
                pane = .history
            }
        }
    }

    private var panePicker: some View {
        Picker("Exercise detail pane", selection: $pane) {
            ForEach(Pane.allCases) { option in
                Text(option.title).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: pane) { _, _ in
            HapticEngine.shared.play(.selection)
        }
        .accessibilityLabel("Exercise detail sections")
    }

    private var formSection: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.lg) {
            if let imageURL = model.imageURL {
                Card {
                    VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                        HelmSectionEyebrow("DEMO")
                        ExerciseImageView(
                            url: imageURL,
                            fallbackLabel: model.exerciseName
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: HelmLayout.exerciseHistoryImageHeight)
                        .accessibilityLabel("\(model.exerciseName) demonstration")
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                    HelmSectionEyebrow("INSTRUCTION")
                    if let instruction = model.instructionText {
                        Text(instruction)
                            .helmType(.body, color: HelmColor.fg)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        emptyState("No instruction text for this exercise.")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Card {
                VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                    HelmSectionEyebrow("CUES")
                    if model.coachingCues.isEmpty {
                        emptyState("No coaching cues seeded for this exercise.")
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(model.coachingCues.enumerated()), id: \.offset) { index, cue in
                                HelmRuledRow {
                                    HStack(alignment: .top, spacing: HelmSpacing.sm) {
                                        Text(String(format: "%02d", index + 1))
                                            .helmType(.monoTag, color: HelmColor.fgMuted)
                                            .frame(width: 28, alignment: .leading)
                                        Text(cue)
                                            .helmType(.body, color: HelmColor.fg)
                                            .fixedSize(horizontal: false, vertical: true)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.lg) {
            if let currentE1RM = model.currentE1RMKilograms {
                Card {
                    VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                        HelmSectionEyebrow("CURRENT e1RM")
                        HelmNumericText(currentE1RM, format: "%.0f kg")
                            .helmType(.bigNumber, color: HelmColor.accent)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            previousSection
            e1rmHistorySection
        }
    }

    private var previousSection: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            HelmSectionEyebrow("PREV")

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
            HelmSectionEyebrow("e1RM HISTORY")

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
            .padding(.vertical, HelmSpacing.xxs)
    }
}

#Preview("Exercise detail") {
    ExerciseHistorySheet(model: .benchFixture)
        .helmTheme()
}

#Preview("Exercise detail cold start") {
    ExerciseHistorySheet(model: .coldStartFixture)
        .helmTheme()
}

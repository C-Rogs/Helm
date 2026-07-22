import Core
import DesignSystem
import Persistence
import SwiftUI

struct WorkoutImportPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var controller: WorkoutImportController
    let onImported: () -> Void

    @State private var mappingExerciseTitle: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HelmSpacing.md) {
                    VStack(alignment: .leading, spacing: HelmSpacing.xs) {
                        Text("Workout title")
                            .font(HelmTypography.caption)
                            .foregroundStyle(HelmColor.textSecondary)
                        TextField("Workout title", text: $controller.workoutTitle)
                            .font(HelmTypography.body)
                            .padding(HelmSpacing.sm)
                            .background(HelmColor.surface)
                            .clipShape(RoundedRectangle(cornerRadius: HelmRadius.md))
                    }

                    DatePicker("Workout date", selection: $controller.workoutDate, displayedComponents: [.date, .hourAndMinute])
                        .font(HelmTypography.body)
                        .foregroundStyle(HelmColor.textPrimary)

                    if let skippedCount = controller.parsedWorkout?.skippedLines.count, skippedCount > 0 {
                        Text("\(skippedCount) line(s) could not be parsed and were skipped.")
                            .font(HelmTypography.caption)
                            .foregroundStyle(HelmColor.warning)
                    }

                    Text("Exercises")
                        .font(HelmTypography.headline)
                        .foregroundStyle(HelmColor.textPrimary)

                    ForEach(controller.resolutions) { resolution in
                        exerciseCard(resolution)
                    }

                    if let errorMessage = controller.errorMessage {
                        Text(errorMessage)
                            .font(HelmTypography.caption)
                            .foregroundStyle(HelmColor.destructive)
                    }

                    Button("Import to history") {
                        controller.importToHistory {
                            onImported()
                            dismiss()
                        }
                    }
                    .buttonStyle(.helmPrimary)
                    .disabled(!controller.canImport)
                }
                .padding(HelmSpacing.md)
            }
            .helmScreenBackground()
            .navigationTitle("Import preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") {
                        controller.isShowingPreview = false
                    }
                }
            }
            .sheet(isPresented: mappingSheetPresented) {
                if let title = mappingExerciseTitle {
                    ExercisePickerView(
                        fetchExercises: controller.fetchPickerExercises(search:),
                        onSelect: { exerciseID in
                            controller.mapExercise(importedTitle: title, to: exerciseID)
                            mappingExerciseTitle = nil
                        }
                    )
                }
            }
        }
        .helmTheme()
    }

    @ViewBuilder
    private func exerciseCard(_ resolution: WorkoutImportExerciseResolution) -> some View {
        let parsedExercise = controller.parsedWorkout?.exercises.first { $0.exerciseTitle == resolution.importedTitle }

        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                        Text(resolution.importedTitle)
                            .font(HelmTypography.body)
                            .foregroundStyle(HelmColor.textPrimary)
                        if let exerciseID = resolution.exerciseID {
                            Text(controller.displayName(for: exerciseID))
                                .font(HelmTypography.caption)
                                .foregroundStyle(HelmColor.textSecondary)
                        }
                    }
                    Spacer(minLength: HelmSpacing.sm)
                    matchBadge(for: resolution.matchKind)
                }

                if let parsedExercise {
                    Text(setSummary(for: parsedExercise))
                        .font(HelmTypography.caption.monospacedDigit())
                        .foregroundStyle(HelmColor.textSecondary)
                }

                if resolution.matchKind == .unresolved || resolution.matchKind == .manual {
                    Button(resolution.isResolved ? "Change exercise" : "Map exercise") {
                        mappingExerciseTitle = resolution.importedTitle
                    }
                    .buttonStyle(.helmSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func setSummary(for exercise: ParsedWorkoutExercise) -> String {
        let parts = exercise.sets.map { set -> String in
            let weight = set.mass.map { String(format: "%.0f kg", $0.kilograms) } ?? "BW"
            let reps = set.reps.map(String.init) ?? "-"
            var line = "\(weight) x \(reps)"
            if set.setType == .warmup { line += " warmup" }
            if let rpe = set.rpe { line += " @\(formatRPE(rpe))" }
            return line
        }
        return "\(exercise.sets.count) sets: \(parts.joined(separator: ", "))"
    }

    private func formatRPE(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
    }

    @ViewBuilder
    private func matchBadge(for kind: WorkoutImportMatchKind) -> some View {
        switch kind {
        case .alias, .displayName, .manual:
            statusBadge(label: "Matched", color: HelmColor.positive)
        case .unresolved:
            statusBadge(label: "Map", color: HelmColor.warning)
        }
    }

    private func statusBadge(label: String, color: Color) -> some View {
        Text(label)
            .font(HelmTypography.caption)
            .foregroundStyle(color)
            .padding(.horizontal, HelmSpacing.xs)
            .padding(.vertical, HelmSpacing.xxs)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }

    private var mappingSheetPresented: Binding<Bool> {
        Binding(
            get: { mappingExerciseTitle != nil },
            set: { isPresented in
                if !isPresented { mappingExerciseTitle = nil }
            }
        )
    }
}

#Preview {
    WorkoutImportPreviewView(
        controller: WorkoutImportController(persistence: try! PersistenceStore.inMemory()),
        onImported: {}
    )
}

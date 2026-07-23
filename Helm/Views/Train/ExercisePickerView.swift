import Core
import DesignSystem
import SwiftUI

struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss

    let fetchExercises: (String) throws -> [ExerciseSummary]
    let onSelect: (String) -> Void

    @State private var searchText = ""
    @State private var exercises: [ExerciseSummary] = []
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            Group {
                if let loadError {
                    Text(loadError)
                        .font(HelmTypography.body)
                        .foregroundStyle(HelmColor.destructive)
                        .padding()
                } else if exercises.isEmpty {
                    ContentUnavailableView(
                        "No exercises",
                        systemImage: "dumbbell",
                        description: Text("Exercise library is still loading or unavailable.")
                    )
                } else {
                    List(exercises) { exercise in
                        Button {
                            onSelect(exercise.id)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                                Text(exercise.displayName)
                                    .font(HelmTypography.body)
                                    .foregroundStyle(HelmColor.textPrimary)
                                if let muscle = exercise.primaryMuscleGroup {
                                    Text(muscle.capitalized)
                                        .font(HelmTypography.caption)
                                        .foregroundStyle(HelmColor.textSecondary)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .helmScreenBackground()
            .navigationTitle("Add exercise")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search exercises")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { reload() }
            .onChange(of: searchText) { _, _ in reload() }
        }
        .helmTheme()
    }

    private func reload() {
        do {
            exercises = try fetchExercises(searchText)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}

#Preview("Exercise picker") {
    ExercisePickerView(
        fetchExercises: { _ in
            [
                ExerciseSummary(
                    id: "1",
                    displayName: "Bench Press (Barbell)",
                    exerciseMode: .weightReps,
                    isCustom: false,
                    primaryMuscleGroup: "chest"
                ),
                ExerciseSummary(
                    id: "2",
                    displayName: "Squat (Barbell)",
                    exerciseMode: .weightReps,
                    isCustom: false,
                    primaryMuscleGroup: "quads"
                )
            ]
        },
        onSelect: { _ in }
    )
}

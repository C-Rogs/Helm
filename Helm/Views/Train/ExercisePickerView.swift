import Core
import DesignSystem
import SwiftUI

struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss

    let fetchRecent: () throws -> [ExerciseSummary]
    let fetchMuscleGroups: () throws -> [String]
    let fetchExercises: (String, String?) throws -> [ExerciseSummary]
    let onSelect: (String) -> Void

    @State private var searchText = ""
    @State private var selectedMuscleGroup: String?
    @State private var recentExercises: [ExerciseSummary] = []
    @State private var muscleGroups: [String] = []
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
                } else if exercises.isEmpty, recentExercises.isEmpty {
                    ContentUnavailableView(
                        "No exercises",
                        systemImage: "dumbbell",
                        description: Text("Exercise library is still loading or unavailable.")
                    )
                } else {
                    List {
                        if !recentExercises.isEmpty, searchText.isEmpty, selectedMuscleGroup == nil {
                            Section("Recent") {
                                exerciseRows(recentExercises)
                            }
                        }

                        if !muscleGroups.isEmpty {
                            Section("Muscle group") {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: HelmSpacing.xs) {
                                        filterChip(label: "All", isSelected: selectedMuscleGroup == nil) {
                                            selectedMuscleGroup = nil
                                            reload()
                                        }
                                        ForEach(muscleGroups, id: \.self) { muscle in
                                            filterChip(
                                                label: muscle.capitalized,
                                                isSelected: selectedMuscleGroup == muscle
                                            ) {
                                                selectedMuscleGroup = muscle
                                                reload()
                                            }
                                        }
                                    }
                                    .padding(.vertical, HelmSpacing.xxs)
                                }
                                .listRowInsets(EdgeInsets())
                            }
                        }

                        Section("Exercises") {
                            exerciseRows(exercises)
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
            .onAppear { reloadAll() }
            .onChange(of: searchText) { _, _ in reload() }
        }
        .helmTheme()
    }

    @ViewBuilder
    private func exerciseRows(_ items: [ExerciseSummary]) -> some View {
        ForEach(items) { exercise in
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
    }

    private func filterChip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(HelmTypography.caption)
                .padding(.horizontal, HelmSpacing.sm)
                .padding(.vertical, HelmSpacing.xxs)
                .background(isSelected ? HelmColor.accent.opacity(0.2) : HelmColor.surface)
                .foregroundStyle(isSelected ? HelmColor.accent : HelmColor.fgSecondary)
                .clipShape(Capsule())
                .overlay {
                    Capsule().strokeBorder(HelmColor.hairline, lineWidth: 1)
                }
        }
        .buttonStyle(.helmPressable)
    }

    private func reloadAll() {
        do {
            recentExercises = try fetchRecent()
            muscleGroups = try fetchMuscleGroups()
            reload()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func reload() {
        do {
            exercises = try fetchExercises(searchText, selectedMuscleGroup)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}

#Preview("Exercise picker") {
    ExercisePickerView(
        fetchRecent: { [] },
        fetchMuscleGroups: { ["chest", "back"] },
        fetchExercises: { _, _ in
            [
                ExerciseSummary(
                    id: "1",
                    displayName: "Bench Press (Barbell)",
                    exerciseMode: .weightReps,
                    isCustom: false,
                    primaryMuscleGroup: "chest"
                )
            ]
        },
        onSelect: { _ in }
    )
}

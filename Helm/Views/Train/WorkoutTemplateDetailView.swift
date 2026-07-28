import Core
import DesignSystem
import SwiftUI

struct WorkoutTemplateDetailView: View {
    @Bindable var history: WorkoutHistoryController
    let templateID: String
    let onStart: () -> Void

    @State private var draft: WorkoutTemplateDraft?
    @State private var name = ""
    @State private var notes = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            if let draft {
                Section("Template") {
                    TextField("Name", text: $name)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2 ... 4)
                }

                Section("Exercises") {
                    ForEach(draft.exercises.sorted(by: { $0.displayOrder < $1.displayOrder })) { exercise in
                        VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                            Text(history.displayName(for: exercise.exerciseID))
                                .helmType(.body)
                            Text(templateTargetText(for: exercise))
                                .helmType(.body, color: HelmColor.fgSecondary)
                        }
                    }
                    .onMove(perform: moveExercise)
                }

                Section {
                    Button("Start workout", action: onStart)
                    Button("Save changes") {
                        saveChanges(base: draft)
                    }
                    Button("Delete template", role: .destructive) {
                        history.deleteTemplate(id: templateID)
                        dismiss()
                    }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Template")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            EditButton()
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard let loaded = history.fetchTemplate(id: templateID) else { return }
        draft = loaded
        name = loaded.name
        notes = loaded.notes ?? ""
        history.refresh()
    }

    private func saveChanges(base: WorkoutTemplateDraft) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let updated = WorkoutTemplateDraft(
            id: base.id,
            name: trimmedName,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            exercises: base.exercises
        )
        history.updateTemplate(updated)
        draft = updated
    }

    private func moveExercise(from source: IndexSet, to destination: Int) {
        guard var current = draft else { return }
        var ordered = current.exercises.sorted(by: { $0.displayOrder < $1.displayOrder })
        ordered.move(fromOffsets: source, toOffset: destination)
        let reordered = ordered.enumerated().map { index, exercise in
            WorkoutTemplateExerciseDraft(
                id: exercise.id,
                exerciseID: exercise.exerciseID,
                displayOrder: index,
                targetSetCount: exercise.targetSetCount,
                targetRepMin: exercise.targetRepMin,
                targetRepMax: exercise.targetRepMax,
                targetMass: exercise.targetMass,
                defaultRestSeconds: exercise.defaultRestSeconds
            )
        }
        current = WorkoutTemplateDraft(
            id: current.id,
            name: current.name,
            notes: current.notes,
            exercises: reordered
        )
        draft = current
    }

    private func templateTargetText(for exercise: WorkoutTemplateExerciseDraft) -> String {
        var parts: [String] = []
        if let sets = exercise.targetSetCount {
            let repMin = exercise.targetRepMin
            let repMax = exercise.targetRepMax
            switch (repMin, repMax) {
            case let (min?, max?) where min == max:
                parts.append("\(sets)×\(min)")
            case let (min?, max?):
                parts.append("\(sets)×\(min)-\(max)")
            case let (min?, nil):
                parts.append("\(sets)×\(min)")
            default:
                parts.append("\(sets) sets")
            }
        }
        if let mass = exercise.targetMass {
            parts.append(String(format: "%.0f kg", mass.kilograms))
        }
        return parts.joined(separator: " · ")
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

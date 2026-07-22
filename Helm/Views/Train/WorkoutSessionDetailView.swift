import Core
import DesignSystem
import SwiftUI

struct WorkoutSessionDetailView: View {
    let sessionID: String
    @Bindable var history: WorkoutHistoryController

    @State private var draft: WorkoutSessionDraft?
    @State private var templateName = ""
    @State private var isShowingSaveTemplate = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HelmSpacing.md) {
                if let draft {
                    ForEach(draft.exercises) { exercise in
                        Card {
                            VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                                Text(history.displayName(for: exercise.exerciseID))
                                    .font(HelmTypography.headline)
                                    .foregroundStyle(HelmColor.textPrimary)

                                ForEach(exercise.sets) { set in
                                    EditableSetRow(
                                        set: set,
                                        onUpdate: { updated in
                                            updateSet(exerciseID: exercise.id, set: updated)
                                        }
                                    )
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    Button("Save changes") {
                        history.saveSession(draft)
                    }
                    .buttonStyle(.helmPrimary)

                    Button("Save as template") {
                        isShowingSaveTemplate = true
                    }
                    .buttonStyle(.helmSecondary)
                } else {
                    ProgressView()
                }
            }
            .padding(HelmSpacing.md)
        }
        .navigationTitle(draft?.title ?? "Workout")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            draft = history.fetchSession(id: sessionID)
        }
        .alert("Template name", isPresented: $isShowingSaveTemplate) {
            TextField("Push Day", text: $templateName)
            Button("Save") {
                if let draft, !templateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    history.createTemplate(from: draft, name: templateName)
                    templateName = ""
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func updateSet(exerciseID: String, set: SetEntryDraft) {
        guard var draft else { return }
        draft = WorkoutSessionDraft(
            id: draft.id,
            title: draft.title,
            startedAt: draft.startedAt,
            endedAt: draft.endedAt,
            status: draft.status,
            source: draft.source,
            exercises: draft.exercises.map { exercise in
                guard exercise.id == exerciseID else { return exercise }
                return WorkoutSessionExerciseDraft(
                    id: exercise.id,
                    exerciseID: exercise.exerciseID,
                    displayOrder: exercise.displayOrder,
                    exerciseMode: exercise.exerciseMode,
                    sets: exercise.sets.map { $0.id == set.id ? set : $0 }
                )
            }
        )
        self.draft = draft
    }
}

private struct EditableSetRow: View {
    let set: SetEntryDraft
    let onUpdate: (SetEntryDraft) -> Void

    @State private var weightText = ""
    @State private var repsText = ""

    var body: some View {
        HStack {
            Text("Set \(set.setIndex + 1)")
                .font(HelmTypography.caption)
                .foregroundStyle(HelmColor.textSecondary)
                .frame(width: 48, alignment: .leading)

            TextField("kg", text: $weightText)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .onChange(of: weightText) { _, newValue in
                    let mass = Double(newValue).map { Mass(kilograms: $0) }
                    onUpdate(updatedSet(mass: mass))
                }

            TextField("reps", text: $repsText)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .onChange(of: repsText) { _, newValue in
                    let reps = Int(newValue)
                    onUpdate(updatedSet(reps: reps))
                }
        }
        .onAppear {
            if let mass = set.mass {
                weightText = String(format: mass.kilograms.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f", mass.kilograms)
            }
            if let reps = set.reps {
                repsText = String(reps)
            }
        }
    }

    private func updatedSet(mass: Mass? = nil, reps: Int? = nil) -> SetEntryDraft {
        SetEntryDraft(
            id: set.id,
            setIndex: set.setIndex,
            setType: set.setType,
            status: set.status,
            mass: mass ?? set.mass,
            reps: reps ?? set.reps,
            distanceKilometers: set.distanceKilometers,
            durationSeconds: set.durationSeconds,
            rpe: set.rpe,
            rir: set.rir,
            completedAt: set.completedAt
        )
    }
}

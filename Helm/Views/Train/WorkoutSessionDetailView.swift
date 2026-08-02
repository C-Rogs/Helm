import Core
import DesignSystem
import Persistence
import SwiftUI
import UIKit

struct WorkoutSessionDetailView: View {
    let sessionID: String
    @Bindable var history: WorkoutHistoryController
    var matchedCardNamespace: Namespace.ID? = nil

    @State private var draft: WorkoutSessionDraft?
    @State private var templateName = ""
    @State private var isShowingSaveTemplate = false
    @State private var didCopyExport = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HelmSpacing.md) {
                if let draft {
                    if let matchedCardNamespace {
                        sessionHeaderCard(for: draft)
                            .helmMatchedCardDetail(id: sessionID, in: matchedCardNamespace, isSource: false)
                    }

                    Card {
                        VStack(spacing: 0) {
                            ForEach(draft.exercises) { exercise in
                                HelmRuledRow {
                                    VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                                        Text(history.displayName(for: exercise.exerciseID))
                                            .helmType(.label)

                                        ForEach(exercise.sets) { set in
                                            EditableSetRow(
                                                set: set,
                                                onUpdate: { updated in
                                                    updateSet(exerciseID: exercise.id, set: updated)
                                                }
                                            )
                                        }
                                    }
                                }
                            }
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
            .helmScreenPadding()
        }
        .navigationTitle(draft?.title ?? "Workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if draft != nil {
                    Button("Export") {
                        exportWorkout()
                    }
                }
            }
        }
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
        .alert("Copied", isPresented: $didCopyExport) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Workout copied for Gemini verification.")
        }
    }

    private func exportWorkout() {
        guard let draft else { return }
        var names: [String: String] = [:]
        for exercise in draft.exercises {
            names[exercise.exerciseID] = history.displayName(for: exercise.exerciseID)
        }
        let text = WorkoutExportFormatter.formatForClipboard(draft: draft, displayNames: names)
        UIPasteboard.general.string = text
        didCopyExport = true
    }

    private func sessionHeaderCard(for draft: WorkoutSessionDraft) -> some View {
        let summary = history.sessions.first(where: { $0.id == sessionID })
        let totalSets = summary?.totalSetCount ?? draft.exercises.reduce(0) { $0 + $1.sets.count }
        let totalVolume = summary?.totalVolumeKilograms ?? draft.exercises
            .flatMap(\.sets)
            .reduce(0.0) { partial, set in
                guard let mass = set.mass, let reps = set.reps else { return partial }
                return partial + mass.kilograms * Double(reps)
            }

        return Card {
            VStack(alignment: .leading, spacing: HelmSpacing.xs) {
                Text(draft.title ?? "Workout")
                    .helmFont(.body)
                    .foregroundStyle(HelmColor.textPrimary)
                Text(draft.startedAt, style: .date)
                    .helmFont(.body)
                    .foregroundStyle(HelmColor.textSecondary)
                HStack(spacing: HelmSpacing.md) {
                    Label {
                        HStack(spacing: HelmSpacing.xxs) {
                            HelmNumericText(totalSets)
                            Text("sets")
                        }
                    } icon: {
                        Image(systemName: "checkmark.circle")
                    }
                    Label {
                        HStack(spacing: HelmSpacing.xxs) {
                            HelmNumericText(totalVolume, format: "%.0f")
                            Text("kg")
                        }
                    } icon: {
                        Image(systemName: "scalemass")
                    }
                }
                .helmFont(.body)
                .foregroundStyle(HelmColor.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
                .helmFont(.body)
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

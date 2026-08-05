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
    @State private var savedSnapshot: WorkoutSessionDraft?
    @State private var isEditing = false
    @State private var templateName = ""
    @State private var isShowingSaveTemplate = false
    @State private var isShowingDeleteConfirm = false
    @State private var isShowingDiscardConfirm = false
    @State private var didCopyExport = false
    @Environment(\.dismiss) private var dismiss

    private var summary: WorkoutSessionSummary? {
        history.sessions.first(where: { $0.id == sessionID })
    }

    private var hasUnsavedChanges: Bool {
        guard let draft, let savedSnapshot else { return false }
        return draft != savedSnapshot
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HelmSpacing.md) {
                if let draft {
                    sessionSummaryCard(for: draft)
                        .modifier(MatchedCardModifier(sessionID: sessionID, namespace: matchedCardNamespace))

                    ForEach(draft.exercises) { exercise in
                        exerciseSection(for: exercise)
                    }

                    if isEditing {
                        editActions
                    }

                    if let errorMessage = history.errorMessage {
                        HelmErrorState(
                            title: "Could not save workout",
                            message: errorMessage,
                            onRetry: nil
                        )
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, HelmSpacing.xl)
                }
            }
            .helmScreenPadding()
            .padding(.bottom, HelmLayout.trainScrollBottomInset)
        }
        .helmScreenBackground()
        .navigationTitle(draft?.title ?? "Workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if isEditing {
                    Button("Cancel") {
                        requestCancelEditing()
                    }
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                if draft != nil {
                    if isEditing {
                        Button("Save") {
                            saveChanges()
                        }
                        .disabled(!hasUnsavedChanges)
                    } else {
                        Button("Edit") {
                            beginEditing()
                        }
                    }
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                if draft != nil, !isEditing {
                    overflowMenu
                }
            }
        }
        .task {
            loadSession()
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
        .confirmationDialog(
            "Delete this workout?",
            isPresented: $isShowingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete workout", role: .destructive) {
                if history.deleteSession(id: sessionID) {
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes it from history. This cannot be undone.")
        }
        .confirmationDialog(
            "Discard changes?",
            isPresented: $isShowingDiscardConfirm,
            titleVisibility: .visible
        ) {
            Button("Discard changes", role: .destructive) {
                discardEditing()
            }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text("Unsaved edits will be lost.")
        }
    }

    private var overflowMenu: some View {
        Menu {
            Button("Export") {
                exportWorkout()
            }
            Button("Save as template") {
                templateName = draft?.title ?? ""
                isShowingSaveTemplate = true
            }
            Button("Delete workout", role: .destructive) {
                isShowingDeleteConfirm = true
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: HelmIconContext.inline.pointSize, weight: HelmIconContext.inline.weight))
                .foregroundStyle(HelmColor.fgSecondary)
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("Workout actions")
    }

    private var editActions: some View {
        VStack(spacing: HelmSpacing.sm) {
            Text("Editing sets")
                .helmType(.body, color: HelmColor.fgSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("Save changes") {
                saveChanges()
            }
            .buttonStyle(.helmPrimary)
            .disabled(!hasUnsavedChanges)
        }
    }

    private func loadSession() {
        let loaded = history.fetchSession(id: sessionID)
        draft = loaded
        savedSnapshot = loaded
    }

    private func beginEditing() {
        savedSnapshot = draft
        isEditing = true
    }

    private func requestCancelEditing() {
        if hasUnsavedChanges {
            isShowingDiscardConfirm = true
        } else {
            discardEditing()
        }
    }

    private func discardEditing() {
        draft = savedSnapshot
        isEditing = false
    }

    private func saveChanges() {
        guard let draft else { return }
        if history.saveSession(draft) {
            savedSnapshot = draft
            isEditing = false
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

    @ViewBuilder
    private func sessionSummaryCard(for draft: WorkoutSessionDraft) -> some View {
        let totalSets = summary?.totalSetCount ?? draft.exercises.reduce(0) { $0 + $1.sets.count }
        let totalReps = summary?.totalRepCount ?? draft.exercises
            .flatMap(\.sets)
            .compactMap(\.reps)
            .reduce(0, +)
        let totalVolume = summary?.totalVolumeKilograms ?? draft.exercises
            .flatMap(\.sets)
            .reduce(0.0) { partial, set in
                guard let mass = set.mass, let reps = set.reps else { return partial }
                return partial + mass.kilograms * Double(reps)
            }
        let exerciseCount = summary?.exerciseCount ?? draft.exercises.count

        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                    Text(draft.title ?? "Workout")
                        .helmType(.label)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(WorkoutHistoryFormatting.contextualDateTimeLabel(draft.startedAt))
                        .helmType(.body, color: HelmColor.fgSecondary)
                }

                HStack(spacing: HelmSpacing.sm) {
                    summaryStat(label: "TIME", value: durationValue(for: draft), unit: "min")
                    summaryStat(label: "EX", value: "\(exerciseCount)", unit: nil)
                    summaryStat(label: "SETS", value: "\(totalSets)", unit: nil)
                    summaryStat(label: "REPS", value: "\(totalReps)", unit: nil)
                }

                HStack(spacing: HelmSpacing.sm) {
                    summaryStat(
                        label: "VOLUME",
                        value: WorkoutHistoryFormatting.volumeLabel(kilograms: totalVolume),
                        unit: "kg"
                    )
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func durationValue(for draft: WorkoutSessionDraft) -> String {
        if let minutes = WorkoutHistoryFormatting.durationMinutes(
            startedAt: draft.startedAt,
            endedAt: draft.endedAt
        ) {
            return "\(minutes)"
        }
        return "-"
    }

    private func summaryStat(label: String, value: String, unit: String?) -> some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
            Text(label)
                .helmType(.monoTag, color: HelmColor.fgMuted)
            HStack(alignment: .firstTextBaseline, spacing: HelmSpacing.xxs) {
                Text(value)
                    .helmType(.number, color: HelmColor.fg)
                    .monospacedDigit()
                if let unit {
                    Text(unit)
                        .helmType(.body, color: HelmColor.fgMuted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func exerciseSection(for exercise: WorkoutSessionExerciseDraft) -> some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            Text(history.displayName(for: exercise.exerciseID))
                .helmType(.label)

            Card {
                VStack(spacing: 0) {
                    ForEach(exercise.sets) { set in
                        HelmRuledRow {
                            if isEditing {
                                EditableSetRow(
                                    set: set,
                                    onUpdate: { updated in
                                        updateSet(exerciseID: exercise.id, set: updated)
                                    }
                                )
                            } else {
                                ReadOnlySetRow(set: set)
                            }
                        }
                    }
                }
            }
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

private struct MatchedCardModifier: ViewModifier {
    let sessionID: String
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.helmMatchedCardDetail(id: sessionID, in: namespace, isSource: false)
        } else {
            content
        }
    }
}

private struct ReadOnlySetRow: View {
    let set: SetEntryDraft

    var body: some View {
        HStack(alignment: .center, spacing: HelmSpacing.sm) {
            Text("\(set.setIndex + 1)")
                .helmType(.monoTag, color: HelmColor.fgMuted)
                .frame(width: 22, alignment: .leading)
                .accessibilityHidden(true)

            Text(setLabel)
                .helmType(.number, color: HelmColor.fg)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)

            if set.status == .completed {
                HelmIconView(.checkmark, context: .inline)
                    .foregroundStyle(HelmColor.accent)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, HelmSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var setLabel: String {
        switch (set.mass, set.reps) {
        case let (mass?, reps?):
            let weight = mass.kilograms.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0f", mass.kilograms)
                : String(format: "%.1f", mass.kilograms)
            return "\(weight) kg × \(reps)"
        case (nil, let reps?):
            return "\(reps) reps"
        case (let mass?, nil):
            let weight = mass.kilograms.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0f", mass.kilograms)
                : String(format: "%.1f", mass.kilograms)
            return "\(weight) kg"
        default:
            return "-"
        }
    }

    private var accessibilityText: String {
        "Set \(set.setIndex + 1), \(setLabel)"
    }
}

private struct EditableSetRow: View {
    let set: SetEntryDraft
    let onUpdate: (SetEntryDraft) -> Void

    @State private var weightText = ""
    @State private var repsText = ""

    var body: some View {
        HStack(alignment: .center, spacing: HelmSpacing.sm) {
            Text("\(set.setIndex + 1)")
                .helmType(.monoTag, color: HelmColor.fgMuted)
                .frame(width: 22, alignment: .leading)
                .accessibilityLabel("Set \(set.setIndex + 1)")

            VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                Text("kg")
                    .helmType(.monoTag, color: HelmColor.fgMuted)
                TextField("-", text: $weightText)
                    .keyboardType(.decimalPad)
                    .helmType(.number, color: HelmColor.fg)
                    .monospacedDigit()
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: weightText) { _, newValue in
                        if newValue.isEmpty {
                            onUpdate(updatedSet(mass: nil, massProvided: true))
                        } else if let kilograms = Double(newValue) {
                            onUpdate(updatedSet(mass: Mass(kilograms: kilograms), massProvided: true))
                        }
                    }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                Text("reps")
                    .helmType(.monoTag, color: HelmColor.fgMuted)
                TextField("-", text: $repsText)
                    .keyboardType(.numberPad)
                    .helmType(.number, color: HelmColor.fg)
                    .monospacedDigit()
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: repsText) { _, newValue in
                        if newValue.isEmpty {
                            onUpdate(updatedSet(reps: nil, repsProvided: true))
                        } else if let reps = Int(newValue) {
                            onUpdate(updatedSet(reps: reps, repsProvided: true))
                        }
                    }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, HelmSpacing.xs)
        .onAppear {
            syncFieldsFromSet()
        }
        .onChange(of: set.id) { _, _ in
            syncFieldsFromSet()
        }
    }

    private func syncFieldsFromSet() {
        if let mass = set.mass {
            weightText = String(
                format: mass.kilograms.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f",
                mass.kilograms
            )
        } else {
            weightText = ""
        }
        if let reps = set.reps {
            repsText = String(reps)
        } else {
            repsText = ""
        }
    }

    private func updatedSet(
        mass: Mass? = nil,
        massProvided: Bool = false,
        reps: Int? = nil,
        repsProvided: Bool = false
    ) -> SetEntryDraft {
        SetEntryDraft(
            id: set.id,
            setIndex: set.setIndex,
            setType: set.setType,
            status: set.status,
            mass: massProvided ? mass : set.mass,
            reps: repsProvided ? reps : set.reps,
            distanceKilometers: set.distanceKilometers,
            durationSeconds: set.durationSeconds,
            rpe: set.rpe,
            rir: set.rir,
            completedAt: set.completedAt
        )
    }
}

#Preview("Workout detail review") {
    NavigationStack {
        WorkoutSessionDetailView(
            sessionID: "preview",
            history: TrainBootstrap.historyController
        )
    }
    .helmTheme()
}

#Preview("Workout detail accessibility") {
    NavigationStack {
        WorkoutSessionDetailView(
            sessionID: "preview",
            history: TrainBootstrap.historyController
        )
    }
    .helmTheme()
    .dynamicTypeSize(.accessibility3)
}

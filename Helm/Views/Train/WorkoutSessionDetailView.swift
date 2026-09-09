import Core
import DesignSystem
import HealthKitIngest
import Persistence
import SwiftUI
import UIKit

struct WorkoutSessionDetailView: View {
    let sessionID: String
    @Bindable var history: WorkoutHistoryController
    var matchedCardNamespace: Namespace.ID? = nil
    var isDeleted: Bool = false

    @State private var draft: WorkoutSessionDraft?
    @State private var savedSnapshot: WorkoutSessionDraft?
    @State private var finishSummary: WorkoutFinishSummary?
    @State private var isEditing = false
    @State private var templateName = ""
    @State private var isShowingSaveTemplate = false
    @State private var isShowingDeleteConfirm = false
    @State private var isShowingRestoreConfirm = false
    @State private var isShowingDiscardConfirm = false
    @State private var didCopyExport = false
    @Environment(\.dismiss) private var dismiss

    private var summary: WorkoutSessionSummary? {
        history.sessions.first(where: { $0.id == sessionID })
            ?? history.activePreviewSessions.first(where: { $0.id == sessionID })
    }

    private var hasUnsavedChanges: Bool {
        guard let draft, let savedSnapshot else { return false }
        return draft != savedSnapshot
    }

    private var isNativeCardio: Bool {
        summary?.isNativeCardio ?? false
    }

    var body: some View {
        if let summary, summary.source == .healthKit {
            healthKitDetailView
        } else {
            strengthDetailView
        }
    }

    private var healthKitDetailView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HelmSpacing.lg) {
                if let summary {
                    healthKitSummaryBlock(for: summary)
                }
            }
            .helmScreenPadding()
            .padding(.bottom, HelmLayout.trainScrollBottomInset + HelmSpacing.xl)
        }
        .helmScreenBackground()
        .navigationTitle(summary?.title ?? "Workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !isDeleted {
                    Menu {
                        if isDeleted {
                            Button("Restore workout") {
                                isShowingRestoreConfirm = true
                            }
                        } else {
                            Button("Move to Bin", role: .destructive) {
                                isShowingDeleteConfirm = true
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: HelmIconContext.inline.pointSize, weight: HelmIconContext.inline.weight))
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete this workout?",
            isPresented: $isShowingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Move to Bin", role: .destructive) {
                if history.deleteSession(id: sessionID) {
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes it from history. Restore anytime from Bin.")
        }
        .confirmationDialog(
            "Restore this workout?",
            isPresented: $isShowingRestoreConfirm,
            titleVisibility: .visible
        ) {
            Button("Restore workout") {
                if history.restoreSession(id: sessionID) {
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Puts it back in your workout history.")
        }
    }

    private var strengthDetailView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HelmSpacing.md) {
                if let draft {
                    leadingSummaryBlock(for: draft)

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
            .padding(.bottom, HelmLayout.trainScrollBottomInset + HelmSpacing.xl)
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
                if draft != nil, !isDeleted {
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
            await loadSession()
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
            Button("Move to Bin", role: .destructive) {
                if history.deleteSession(id: sessionID) {
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes it from history. Restore anytime from Bin.")
        }
        .confirmationDialog(
            "Restore this workout?",
            isPresented: $isShowingRestoreConfirm,
            titleVisibility: .visible
        ) {
            Button("Restore workout") {
                if history.restoreSession(id: sessionID) {
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Puts it back in your workout history.")
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
            if isDeleted {
                Button("Restore workout") {
                    isShowingRestoreConfirm = true
                }
            } else {
                Button("Export") {
                    exportWorkout()
                }
                Button("Save as template") {
                    templateName = draft?.title ?? ""
                    isShowingSaveTemplate = true
                }
                Button("Move to Bin", role: .destructive) {
                    isShowingDeleteConfirm = true
                }
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

    @ViewBuilder
    private func healthKitSummaryBlock(for summary: WorkoutSessionSummary) -> some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.md) {
                HStack {
                    VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                        Text("From Health")
                            .helmType(.monoTag, color: HelmColor.fgMuted)

                        Text(summary.title ?? "Workout")
                            .helmType(.title)
                    }

                    Spacer()
                }

                if let duration = WorkoutHistoryFormatting.durationLabel(
                    startedAt: summary.startedAt,
                    endedAt: summary.endedAt
                ) {
                    HStack(spacing: HelmSpacing.md) {
                        HStack(spacing: HelmSpacing.xxs) {
                            HelmIconView(.train, context: .inline)
                                .foregroundStyle(HelmColor.fgMuted)
                            Text(duration)
                                .helmType(.body, color: HelmColor.fgSecondary)
                        }

                        if let kcal = summary.hkActiveEnergyKilocalories {
                            HStack(spacing: HelmSpacing.xxs) {
                                HelmIconView(.flame, context: .inline)
                                    .foregroundStyle(HelmColor.fgMuted)
                                Text("\(Int(kcal)) kcal")
                                    .helmType(.body, color: HelmColor.fgSecondary)
                            }
                        }

                        if let distance = summary.hkTotalDistanceMeters {
                            HStack(spacing: HelmSpacing.xxs) {
                                HelmIconView(.distance, context: .inline)
                                    .foregroundStyle(HelmColor.fgMuted)
                                Text(WorkoutHistoryFormatting.distanceLabel(meters: distance))
                                    .helmType(.body, color: HelmColor.fgSecondary)
                            }
                        }
                    }
                }

                Text(WorkoutHistoryFormatting.contextualDateTimeLabel(summary.startedAt))
                    .helmType(.body, color: HelmColor.fgMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func leadingSummaryBlock(for draft: WorkoutSessionDraft) -> some View {
        if let finishSummary, !isNativeCardio {
            // No matchedGeometryEffect on the tall summary: source row frame would
            // squeeze it and let the timeline chart paint outside its bounds.
            WorkoutFinishSummaryView(
                summary: finishSummary,
                muscleLabel: TrendsChartSupport.muscleLabel,
                // Nav bar already carries the workout title; avoid repeating it here.
                eyebrow: "SESSION SUMMARY",
                title: WorkoutHistoryFormatting.contextualDateTimeLabel(draft.startedAt),
                playsCompletionHaptic: false,
                horizontalPadding: 0,
                animatesEntrance: false
            )
        } else {
            // Compact card stays the matched-geometry destination until the full
            // finish summary is ready (avoids ghosting + chart height jump).
            sessionSummaryCard(for: draft)
                .helmMatchedCard(id: sessionID, namespace: matchedCardNamespace)
        }
    }

    private func loadSession() async {
        // Sync draft first so the push transition has a matched destination card.
        let loaded = history.fetchSession(id: sessionID)
        draft = loaded
        savedSnapshot = loaded
        finishSummary = nil
        guard let loaded else { return }
        // Wait for timeline-backed summary before swapping off the card.
        finishSummary = await history.finishSummary(for: loaded)
    }

    private func rebuildFinishSummary(from session: WorkoutSessionDraft?) async {
        guard let session else {
            finishSummary = nil
            return
        }
        finishSummary = await history.finishSummary(for: session)
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
            Task {
                await rebuildFinishSummary(from: draft)
            }
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
        let loggedDurationSeconds = draft.exercises
            .flatMap(\.sets)
            .compactMap(\.durationSeconds)
            .reduce(0, +)
        let loggedDistanceKilometers = draft.exercises
            .flatMap(\.sets)
            .compactMap(\.distanceKilometers)
            .reduce(0, +)

        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                    Text(draft.title ?? "Workout")
                        .helmType(.label)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(WorkoutHistoryFormatting.contextualDateTimeLabel(draft.startedAt))
                        .helmType(.body, color: HelmColor.fgSecondary)
                }

                if isNativeCardio {
                    HStack(spacing: HelmSpacing.sm) {
                        summaryStat(label: "TIME", value: durationValue(for: draft), unit: "min")
                        summaryStat(label: "EX", value: "\(exerciseCount)", unit: nil)
                        summaryStat(label: "INTERVALS", value: "\(totalSets)", unit: nil)
                    }
                    HStack(spacing: HelmSpacing.sm) {
                        summaryStat(
                            label: "LOGGED",
                            value: WorkoutHistoryFormatting.intervalDurationLabel(seconds: loggedDurationSeconds),
                            unit: nil
                        )
                        if loggedDistanceKilometers > 0 {
                            summaryStat(
                                label: "DISTANCE",
                                value: formatDistance(loggedDistanceKilometers),
                                unit: "km"
                            )
                        }
                        Spacer(minLength: 0)
                    }
                } else {
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

    private func formatDistance(_ kilometers: Double) -> String {
        kilometers.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", kilometers)
            : String(format: "%.2f", kilometers)
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
                                    exerciseMode: exercise.exerciseMode,
                                    onUpdate: { updated in
                                        updateSet(exerciseID: exercise.id, set: updated)
                                    }
                                )
                            } else {
                                ReadOnlySetRow(set: set, exerciseMode: exercise.exerciseMode)
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

private struct ReadOnlySetRow: View {
    let set: SetEntryDraft
    let exerciseMode: ExerciseMode

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
        if exerciseMode.isCardio {
            var parts: [String] = []
            if let seconds = set.durationSeconds {
                parts.append(
                    WorkoutHistoryFormatting.intervalDurationLabel(seconds: seconds)
                )
            }
            if let distance = set.distanceKilometers {
                parts.append(
                    WorkoutHistoryFormatting.distanceLabel(meters: distance * 1_000)
                )
            }
            if let rpe = set.rpe {
                let value = rpe.truncatingRemainder(dividingBy: 1) == 0
                    ? String(format: "%.0f", rpe)
                    : String(format: "%.1f", rpe)
                parts.append("RPE \(value)")
            }
            return parts.isEmpty ? "-" : parts.joined(separator: " · ")
        }
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
        "\(exerciseMode.isCardio ? "Interval" : "Set") \(set.setIndex + 1), \(setLabel)"
    }
}

private struct EditableSetRow: View {
    let set: SetEntryDraft
    let exerciseMode: ExerciseMode
    let onUpdate: (SetEntryDraft) -> Void

    @State private var weightText = ""
    @State private var repsText = ""
    @State private var durationText = ""
    @State private var distanceText = ""

    var body: some View {
        HStack(alignment: .center, spacing: HelmSpacing.sm) {
            Text("\(set.setIndex + 1)")
                .helmType(.monoTag, color: HelmColor.fgMuted)
                .frame(width: 22, alignment: .leading)
                .accessibilityLabel("Set \(set.setIndex + 1)")

            if exerciseMode.isCardio {
                editableField(label: "min", text: $durationText, decimal: true) { newValue in
                    if newValue.isEmpty {
                        onUpdate(updatedSet(durationSeconds: nil, durationProvided: true))
                    } else if let minutes = Double(newValue) {
                        onUpdate(
                            updatedSet(
                                durationSeconds: Int((minutes * 60).rounded()),
                                durationProvided: true
                            )
                        )
                    }
                }

                if exerciseMode == .distanceDuration {
                    editableField(label: "km", text: $distanceText, decimal: true) { newValue in
                        if newValue.isEmpty {
                            onUpdate(updatedSet(distanceKilometers: nil, distanceProvided: true))
                        } else if let distance = Double(newValue) {
                            onUpdate(updatedSet(distanceKilometers: distance, distanceProvided: true))
                        }
                    }
                }
            } else {
                editableField(label: "kg", text: $weightText, decimal: true) { newValue in
                    if newValue.isEmpty {
                        onUpdate(updatedSet(mass: nil, massProvided: true))
                    } else if let kilograms = Double(newValue) {
                        onUpdate(updatedSet(mass: Mass(kilograms: kilograms), massProvided: true))
                    }
                }

                editableField(label: "reps", text: $repsText, decimal: false) { newValue in
                    if newValue.isEmpty {
                        onUpdate(updatedSet(reps: nil, repsProvided: true))
                    } else if let reps = Int(newValue) {
                        onUpdate(updatedSet(reps: reps, repsProvided: true))
                    }
                }
            }
        }
        .padding(.horizontal, HelmSpacing.xs)
        .onAppear {
            syncFieldsFromSet()
        }
        .onChange(of: set.id) { _, _ in
            syncFieldsFromSet()
        }
    }

    private func editableField(
        label: String,
        text: Binding<String>,
        decimal: Bool,
        onChange: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
            Text(label)
                .helmType(.monoTag, color: HelmColor.fgMuted)
            TextField("-", text: text)
                .keyboardType(decimal ? .decimalPad : .numberPad)
                .helmType(.number, color: HelmColor.fg)
                .monospacedDigit()
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onChange(of: text.wrappedValue) { _, newValue in
                    onChange(newValue)
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        if let seconds = set.durationSeconds {
            let minutes = Double(seconds) / 60
            durationText = minutes.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0f", minutes)
                : String(format: "%.1f", minutes)
        } else {
            durationText = ""
        }
        if let distance = set.distanceKilometers {
            distanceText = String(format: "%.2f", distance)
        } else {
            distanceText = ""
        }
    }

    private func updatedSet(
        mass: Mass? = nil,
        massProvided: Bool = false,
        reps: Int? = nil,
        repsProvided: Bool = false,
        durationSeconds: Int? = nil,
        durationProvided: Bool = false,
        distanceKilometers: Double? = nil,
        distanceProvided: Bool = false
    ) -> SetEntryDraft {
        SetEntryDraft(
            id: set.id,
            setIndex: set.setIndex,
            setType: set.setType,
            status: set.status,
            mass: massProvided ? mass : set.mass,
            reps: repsProvided ? reps : set.reps,
            distanceKilometers: distanceProvided ? distanceKilometers : set.distanceKilometers,
            durationSeconds: durationProvided ? durationSeconds : set.durationSeconds,
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

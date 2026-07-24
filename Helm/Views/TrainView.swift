import Core
import DesignSystem
import HealthKitIngest
import SwiftUI

struct TrainView: View {
    @Bindable private var controller = TrainBootstrap.sessionController
    @Bindable private var history = TrainBootstrap.historyController
    @Bindable private var importController = TrainBootstrap.importController
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.helmReduceMotion) private var reduceMotion

    @State private var restRemainingSeconds: Int?
    @State private var isShowingImport = false
    @State private var didTrackInitialRestRemaining = false
    @FocusState private var isCoachPromptFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Group {
                    if controller.hasActiveSession, let snapshot = controller.snapshot {
                        activeSessionView(snapshot)
                    } else {
                        idleState
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if controller.numpadTarget != nil {
                    numpadOverlay
                }
            }
            .helmScreenBackground()
            .navigationTitle("Train")
            .sheet(isPresented: $isShowingImport) {
                WorkoutImportView(controller: importController)
            }
            .sheet(isPresented: $controller.isShowingExercisePicker) {
                ExercisePickerView(
                    fetchRecent: { try controller.fetchRecentExercises() },
                    fetchMuscleGroups: { try controller.fetchMuscleGroups() },
                    fetchExercises: controller.fetchPickerExercises(search:muscleGroup:),
                    onSelect: { exerciseID in
                        Task { await controller.addExercise(exerciseID: exerciseID) }
                    }
                )
            }
            .confirmationDialog(
                "Finish workout?",
                isPresented: $controller.isShowingFinishConfirmation,
                titleVisibility: .visible
            ) {
                Button("Finish workout", role: .none) {
                    Task {
                        await controller.finishWorkout()
                        history.refresh()
                        history.setRecentPersonalRecords(controller.lastFinishedPersonalRecords)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This saves your logged sets.")
            }
            .confirmationDialog(
                "Discard workout?",
                isPresented: $controller.isShowingDiscardConfirmation,
                titleVisibility: .visible
            ) {
                Button("Discard", role: .destructive) {
                    Task { await controller.discardWorkout() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All progress in this session will be lost.")
            }
            .alert(
                "Workout error",
                isPresented: Binding(
                    get: { controller.errorMessage != nil },
                    set: { if !$0 { controller.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(controller.errorMessage ?? "")
            }
            .sheet(isPresented: $controller.isShowingCoachPrompt) {
                coachPromptSheet
            }
            .sheet(isPresented: $controller.isShowingPersonalRecords) {
                NavigationStack {
                    ScrollView {
                        PersonalRecordsCelebrationView(
                            records: controller.lastFinishedPersonalRecords,
                            exerciseName: controller.displayName(for:)
                        )
                        .padding(HelmSpacing.md)
                    }
                    .helmScreenBackground()
                    .navigationTitle("Personal records")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") {
                                controller.isShowingPersonalRecords = false
                                controller.clearFinishedPersonalRecords()
                            }
                        }
                    }
                }
                .presentationDetents([.medium])
            }
            .task {
                await controller.recoverPersistedSession()
                history.refresh()
            }
            .onChange(of: scenePhase) { _, newPhase in
                Task { await controller.handleScenePhase(newPhase) }
            }
        }
    }

    private var idleState: some View {
        ScrollView {
            HelmScreenStack {
                if let summary = controller.prescriptionSummary, !summary.exercises.isEmpty {
                    prescriptionIdleCard(summary)
                } else {
                    manualIdleCard
                }

                if !history.recentPersonalRecords.isEmpty {
                    PersonalRecordsCelebrationView(
                        records: history.recentPersonalRecords,
                        exerciseName: history.displayName(for:)
                    )
                }

                WorkoutTemplatesListView(history: history) { templateID in
                    Task { await controller.startWorkout(fromTemplateID: templateID) }
                }

                WorkoutHistoryListView(history: history)
            }
            .helmScreenPadding()
        }
        .onChange(of: isShowingImport) { _, isPresented in
            if !isPresented, !importController.lastImportedPersonalRecords.isEmpty {
                history.refresh()
                history.setRecentPersonalRecords(importController.lastImportedPersonalRecords)
                importController.lastImportedPersonalRecords = []
            }
        }
    }

    private func prescriptionIdleCard(_ summary: PrescribedSessionSummary) -> some View {
        VStack(alignment: .leading, spacing: HelmSpacing.lg) {
            Card {
                VStack(alignment: .leading, spacing: HelmSpacing.md) {
                    HStack {
                        Text("Today's session")
                            .helmType(.label)
                        Spacer()
                        Text(summary.phase.label)
                            .helmType(.monoTag, color: HelmColor.accent)
                    }

                    if summary.readinessAdjusted {
                        Text("Volume trimmed for readiness")
                            .helmType(.monoTag, color: HelmColor.depleted)
                    }

                    ForEach(summary.exercises) { exercise in
                        PrescriptionRow(
                            label: exercise.displayName,
                            target: prescriptionTargetText(for: exercise)
                        )
                    }

                    Text("\(summary.totalSets) total sets")
                        .helmType(.body, color: HelmColor.fgSecondary)
                }
            }

            Button("Start today's session") {
                Task { await controller.startTodaysPrescription() }
            }
            .buttonStyle(.helmPrimary)

            Button("Empty workout") {
                Task { await controller.startWorkout() }
            }
            .buttonStyle(.helmSecondary)

            Button("Import workout") {
                isShowingImport = true
            }
            .buttonStyle(.helmSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, HelmSpacing.md)
    }

    private var manualIdleCard: some View {
        VStack(spacing: HelmSpacing.lg) {
            Text("No active session")
                .font(HelmTypography.body)
                .foregroundStyle(HelmColor.textSecondary)

            Button("Start workout") {
                Task { await controller.startWorkout() }
            }
            .buttonStyle(.helmPrimary)

            Button("Import workout") {
                isShowingImport = true
            }
            .buttonStyle(.helmSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, HelmSpacing.md)
    }

    private func prescriptionTargetText(for exercise: PrescribedExerciseSummary) -> String {
        var parts = ["\(exercise.targetSets)×\(exercise.targetRepRange)"]
        if let load = exercise.targetLoad {
            parts.append(load)
        }
        if let rpe = exercise.targetRPE {
            parts.append(rpe)
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func exerciseSection(for exercise: WorkoutSessionExerciseDraft) -> some View {
        ExerciseSectionView(
            exercise: exercise,
            displayName: controller.displayName(for: exercise.exerciseID),
            targetSummary: controller.targetSummary(for: exercise.exerciseID),
            previousLookup: { set in
                controller.previousFor(set: set, exerciseID: exercise.exerciseID)
            },
            activeField: controller.numpadTarget,
            onOpenField: { sessionExerciseID, field, set in
                controller.openNumpad(
                    setID: set.id,
                    sessionExerciseID: sessionExerciseID,
                    field: field,
                    currentSet: set
                )
            },
            onFillPrevious: { setID in
                Task {
                    await controller.fillFromPrevious(
                        setID: setID,
                        sessionExerciseID: exercise.id
                    )
                }
            },
            onCompleteSet: { sessionExerciseID, setID in
                Task {
                    await controller.completeSet(
                        sessionExerciseID: sessionExerciseID,
                        setID: setID
                    )
                }
            },
            onAddSet: {
                Task { await controller.addSet(sessionExerciseID: exercise.id) }
            },
            onRemoveSet: {
                Task { await controller.removeSet(sessionExerciseID: exercise.id) }
            },
            onRemove: {
                Task { await controller.removeExercise(sessionExerciseID: exercise.id) }
            }
        )
    }

    private func activeSessionView(_ snapshot: ActiveSessionSnapshot) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: HelmSpacing.md) {
                    if let banner = controller.adjustmentBanner {
                        AdjustmentBanner(
                            fromLabel: banner.fromLabel,
                            toLabel: banner.toLabel,
                            reason: banner.reason
                        ) {
                            Task { await controller.undoLastAdjustment() }
                        }
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .opacity
                            )
                        )
                    }

                    if let remaining = restRemainingSeconds {
                        RestTimerBanner(remainingSeconds: remaining) {
                            Task { await controller.skipRest() }
                        }
                    }

                    if snapshot.session.exercises.isEmpty {
                        Text("Add your first exercise to begin logging sets.")
                            .helmType(.body, color: HelmColor.fgSecondary)
                            .padding(.horizontal, HelmSpacing.xs)
                    }

                    ForEach(snapshot.session.exercises) { exercise in
                        exerciseSection(for: exercise)
                    }

                    Button {
                        controller.isShowingExercisePicker = true
                    } label: {
                        Label("Add exercise", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.helmSecondary)

                    Spacer(minLength: bottomContentInset)
                }
                .padding(HelmSpacing.screenGutter)
                .padding(.bottom, HelmSpacing.md)
            }
            .animation(
                HelmMotion.animation(HelmMotion.settleAnimation, reduceMotion: reduceMotion),
                value: controller.adjustmentBanner
            )

            if controller.numpadTarget == nil {
                inSessionCoachBar
                sessionActionBar
            }
        }
        .timelineViewRestTimer(controller: controller, restRemainingSeconds: $restRemainingSeconds)
        .onChange(of: restRemainingSeconds) { _, newValue in
            guard didTrackInitialRestRemaining else {
                didTrackInitialRestRemaining = true
                controller.handleRestRemainingSecondsChange(newValue)
                return
            }
            controller.handleRestRemainingSecondsChange(newValue)
        }
        .task(id: restRemainingSeconds) {
            await controller.syncSideEffects()
        }
    }

    private var bottomContentInset: CGFloat {
        controller.numpadTarget == nil
            ? HelmLayout.trainScrollBottomInset
            : HelmLayout.trainScrollBottomInsetWithNumpad
    }

    private var inSessionCoachBar: some View {
        AskCoachBar(
            prompt: controller.isCoachAdjusting ? "Adjusting session…" : "Ask coach…",
            isLoading: controller.isCoachAdjusting
        ) {
            controller.isShowingCoachPrompt = true
        }
        .padding(.horizontal, HelmSpacing.screenGutter)
        .padding(.bottom, HelmSpacing.xs)
    }

    private var coachPromptSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: HelmSpacing.md) {
                Text("Tell the coach what to change in this session.")
                    .helmType(.body, color: HelmColor.fgSecondary)

                TextField("Cable fly is taken", text: $controller.coachPromptText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3 ... 6)
                    .focused($isCoachPromptFocused)

                Spacer()
            }
            .padding(HelmSpacing.md)
            .helmScreenBackground()
            .navigationTitle("Ask coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        controller.isShowingCoachPrompt = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        Task { await controller.submitCoachPrompt() }
                    }
                    .disabled(controller.coachPromptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                isCoachPromptFocused = true
            }
        }
        .presentationDetents([.medium])
    }

    private var sessionActionBar: some View {
        VStack(spacing: HelmSpacing.xs) {
            Divider()
                .overlay(HelmColor.hairline)
            HStack(spacing: HelmSpacing.sm) {
                Button("Discard") {
                    controller.isShowingDiscardConfirmation = true
                }
                .buttonStyle(.helmSecondary)

                Button("Finish workout") {
                    controller.isShowingFinishConfirmation = true
                }
                .buttonStyle(.helmPrimary)
            }
            .padding(.horizontal, HelmSpacing.screenGutter)
            .padding(.top, HelmSpacing.xs)
            .padding(.bottom, HelmSpacing.sm)
            .background(HelmColor.canvas)
        }
    }

    private var numpadOverlay: some View {
        VStack(spacing: 0) {
            if !controller.numpadWorkingText.isEmpty {
                Text(controller.numpadWorkingText)
                    .helmType(.bigNumber)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, HelmSpacing.sm)
                    .background(HelmColor.surface)
            }

            HelmNumpad(
                allowsDecimal: controller.numpadTarget?.field != .reps,
                onDigit: { controller.appendNumpadDigit($0) },
                onBackspace: { controller.backspaceNumpad() },
                onNext: {
                    Task {
                        await controller.applyNumpadInput()
                        controller.numpadTarget = nil
                    }
                }
            )
            .frame(height: HelmLayout.numpadHeight)
        }
        .background(HelmColor.canvas)
        .transition(.move(edge: .bottom))
    }
}

private struct RestTimerTimelineModifier: ViewModifier {
    let controller: TrainSessionController
    @Binding var restRemainingSeconds: Int?

    func body(content: Content) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            content
                .task(id: context.date) {
                    restRemainingSeconds = await controller.remainingRestSeconds(at: context.date)
                }
        }
    }
}

private extension View {
    func timelineViewRestTimer(
        controller: TrainSessionController,
        restRemainingSeconds: Binding<Int?>
    ) -> some View {
        modifier(RestTimerTimelineModifier(controller: controller, restRemainingSeconds: restRemainingSeconds))
    }
}

#Preview("Train instrument") {
    TrainView()
        .helmTheme()
        .environment(\.helmSkin, .instrument)
}

#Preview("Train data sheet") {
    TrainView()
        .helmTheme()
        .environment(\.helmSkin, .dataSheet)
}

#Preview("Train accessibility") {
    TrainView()
        .helmTheme()
        .dynamicTypeSize(.accessibility5)
}

private extension TrainingPhase {
    var label: String {
        switch self {
        case .cut: "Cut"
        case .maintain: "Maintain"
        case .gain: "Gain"
        }
    }
}

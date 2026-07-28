import Core
import DesignSystem
import HealthKitIngest
import SwiftUI

struct TrainView: View {
    @Bindable private var controller = TrainBootstrap.sessionController
    @Bindable private var history = TrainBootstrap.historyController
    @Bindable private var importController = TrainBootstrap.importController
    @Bindable private var muscleVolumeStore = MuscleVolumeBootstrap.store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.helmReduceMotion) private var reduceMotion

    @State private var isShowingImport = false
    @State private var didTrackInitialRestRemaining = false
    @State private var restEditorExerciseID: String?
    @State private var isShowingSavePrescriptionTemplate = false
    @State private var prescriptionTemplateName = ""

    var body: some View {
        navigationRoot
            .trainPresentationLayer(
                controller: controller,
                history: history,
                muscleVolumeStore: muscleVolumeStore,
                importController: importController,
                isShowingImport: $isShowingImport,
                restEditorExerciseID: $restEditorExerciseID
            )
            .task {
                WatchReadinessBootstrap.coordinator.hydrateFromReceivedApplicationContext()
                await controller.recoverPersistedSession()
                history.refresh()
                muscleVolumeStore.refresh()
            }
            .onChange(of: scenePhase) { _, newPhase in
                Task { await controller.handleScenePhase(newPhase) }
            }
    }

    private var navigationRoot: some View {
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

                VStack(spacing: 0) {
                    if controller.hasActiveSession,
                       let endsAt = controller.snapshot?.restTimer?.endsAt,
                       controller.isRestTimerRunning {
                        RestTimerBanner(
                            endsAt: endsAt,
                            onSkip: {
                                Task { await controller.skipRest() }
                            },
                            onAdjust: { delta in
                                Task { await controller.adjustRestTimer(deltaSeconds: delta) }
                            },
                            onRemainingSecondsChange: { remaining in
                                handleRestTimerTick(remaining)
                            }
                        )
                        .padding(.horizontal, HelmSpacing.screenGutter)
                    }

                    if controller.hasActiveSession,
                       controller.numpadTarget == nil,
                       !controller.isReorderMode {
                        inSessionCoachBar
                    }

                    if controller.numpadTarget != nil {
                        numpadOverlay
                    }
                }
            }
            .helmScreenBackground()
            .navigationTitle("Train")
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

                muscleVolumeBoardSection

                WorkoutTemplatesListView(history: history) { templateID in
                    Task { await controller.startWorkout(fromTemplateID: templateID) }
                }

                WorkoutHistoryListView(history: history)
            }
            .helmScreenPadding()
        }
    }

    private func prescriptionIdleCard(_ summary: PrescribedSessionSummary) -> some View {
        VStack(alignment: .leading, spacing: HelmSpacing.lg) {
            if let staleMessage = controller.staleSessionMessage {
                StaleSessionBanner(
                    message: staleMessage,
                    onDiscuss: { controller.discussTodaysSession() },
                    onRegenerate: {
                        Task { await controller.regenerateTodaysPrescription() }
                    },
                    onDismiss: { controller.dismissStaleSessionBanner() }
                )
            }

            Card {
                VStack(alignment: .leading, spacing: HelmSpacing.md) {
                    HStack {
                        Text("Today's session")
                            .helmType(.label)
                        Spacer()
                        NavigationLink {
                            ProgressionDetailContainer()
                        } label: {
                            HStack(spacing: HelmSpacing.xxs) {
                                Text("Plan")
                                    .helmType(.monoTag, color: HelmColor.accent)
                                HelmIconView(.chevronRight, context: .inline)
                                    .foregroundStyle(HelmColor.fgMuted)
                            }
                        }
                        .buttonStyle(.plain)
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

            Button("Discuss today's session") {
                controller.discussTodaysSession()
            }
            .buttonStyle(.helmSecondary)

            Button("Save as template") {
                prescriptionTemplateName = "Today's session"
                isShowingSavePrescriptionTemplate = true
            }
            .buttonStyle(.helmSecondary)

            Button("Empty workout") {
                Task { await controller.startWorkout() }
            }
            .buttonStyle(.helmSecondary)

            Button("Paste workout plan") {
                isShowingImport = true
            }
            .buttonStyle(.helmSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, HelmSpacing.md)
        .alert("Save as template", isPresented: $isShowingSavePrescriptionTemplate) {
            TextField("Template name", text: $prescriptionTemplateName)
            Button("Save") {
                let name = prescriptionTemplateName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                Task {
                    await controller.saveTodaysPrescriptionAsTemplate(name: name)
                    history.refresh()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Save today's engine prescription as a reusable workout template.")
        }
    }

    private var manualIdleCard: some View {
        VStack(spacing: HelmSpacing.lg) {
            HelmEmptyState(
                title: "No active session",
                message: "Start a workout or paste a plan from your coach.",
                icon: .train,
                actionTitle: "Start workout"
            ) {
                Task { await controller.startWorkout() }
            }

            Button("Paste workout plan") {
                isShowingImport = true
            }
            .buttonStyle(.helmSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, HelmSpacing.md)
    }

    @ViewBuilder
    private var muscleVolumeBoardSection: some View {
        if muscleVolumeStore.isLoading, muscleVolumeStore.model == nil {
            HelmSkeletonCard(rowCount: 4)
        } else if let model = muscleVolumeStore.model {
            Card {
                MuscleVolumeBoardView(model: model, showsHeader: true)
            }
        }
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
            restSeconds: exercise.targetRestSeconds ?? 90,
            isReorderMode: controller.isReorderMode,
            previousLookup: { set in
                controller.previousFor(set: set, exerciseID: exercise.exerciseID)
            },
            activeField: controller.numpadTarget,
            validationMessage: controller.numpadValidationError,
            shakeToken: controller.numpadShakeToken,
            fieldDisplayText: { set, field in
                controller.displayText(for: field, set: set, exerciseID: exercise.exerciseID)
            },
            badgeText: { setID in controller.badgeText(forSetID: setID) },
            encouragementGlyph: { setID in controller.encouragementGlyph(forSetID: setID) },
            showsPRCelebration: { setID in controller.showsPRCelebration(forSetID: setID) },
            onOpenField: { sessionExerciseID, field, set in
                Task {
                    await controller.openNumpad(
                        setID: set.id,
                        sessionExerciseID: sessionExerciseID,
                        field: field,
                        currentSet: set
                    )
                }
            },
            onFillPrevious: { setID in
                Task {
                    await controller.fillFromPrevious(
                        setID: setID,
                        sessionExerciseID: exercise.id
                    )
                }
            },
            onCycleSetType: { setID in
                Task { await controller.cycleSetType(setID: setID) }
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
                controller.requestRemoveExercise(sessionExerciseID: exercise.id)
            },
            onEnterReorderMode: {
                controller.enterReorderMode()
            },
            onEditRest: {
                restEditorExerciseID = exercise.id
            },
            onDropExercise: { sourceID in
                controller.moveExerciseInDraft(from: sourceID, to: exercise.id)
            }
        )
    }

    private func activeSessionView(_ snapshot: ActiveSessionSnapshot) -> some View {
        ZStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: HelmSpacing.md) {
                        SessionHeartRateChip()

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

                        if let proactiveBanner = controller.proactiveCoachBanner {
                            ProactiveCoachBanner(
                                message: proactiveBanner,
                                onDismiss: { controller.dismissProactiveCoachBanner() },
                                onDiscuss: { controller.isShowingCoachPrompt = true }
                            )
                        }

                        SessionCoachNoteField(
                            text: $controller.sessionNoteText,
                            onTextChange: { controller.updateSessionNote($0) },
                            onSaveToMemory: {
                                Task { await controller.saveSessionNoteToMemory() }
                            },
                            savedConfirmation: controller.sessionNoteSavedConfirmation
                        )

                        if snapshot.session.exercises.isEmpty {
                            Text("Add your first exercise to begin logging sets.")
                                .helmType(.body, color: HelmColor.fgSecondary)
                                .padding(.horizontal, HelmSpacing.xs)
                        }

                        ForEach(controller.exercisesForDisplay()) { exercise in
                            exerciseSection(for: exercise)
                        }

                        if !controller.isReorderMode {
                            Button {
                                controller.isShowingExercisePicker = true
                            } label: {
                                Label("Add exercise", helmIcon: .plus, context: .inline)
                            }
                            .buttonStyle(.helmSecondary)
                        }

                        if controller.numpadTarget == nil, !controller.isReorderMode {
                            sessionActionBar
                        }

                        if controller.isReorderMode {
                            reorderActionBar
                        }

                        Spacer(minLength: bottomContentInset)
                    }
                    .padding(HelmSpacing.screenGutter)
                    .padding(.bottom, HelmSpacing.md)
                }
                .animation(
                    HelmMotion.animation(HelmMotion.settleAnimation, reduceMotion: reduceMotion),
                    value: controller.adjustmentBanner
                )
            }

            HelmCoachApplyWave(isActive: $controller.showCoachApplyWave)
        }
    }

    private func handleRestTimerTick(_ remaining: Int) {
        let current = remaining > 0 ? remaining : nil
        if !didTrackInitialRestRemaining {
            didTrackInitialRestRemaining = true
            controller.handleRestRemainingSecondsChange(current)
            return
        }
        controller.handleRestRemainingSecondsChange(current)
        if remaining == 0 {
            controller.handleRestExpiredProactiveCoach()
            Task { await controller.reconcileExpiredRestTimer() }
        }
    }

    private var reorderActionBar: some View {
        HStack(spacing: HelmSpacing.sm) {
            Button("Cancel") {
                controller.cancelReorderMode()
            }
            .buttonStyle(.helmSecondary)

            Button("Done") {
                Task { await controller.commitReorder() }
            }
            .buttonStyle(.helmPrimary)
        }
        .padding(.bottom, HelmSpacing.sm)
    }

    private var bottomContentInset: CGFloat {
        var inset = controller.numpadTarget == nil
            ? HelmLayout.trainScrollBottomInset
            : HelmLayout.trainScrollBottomInsetWithNumpad
        if controller.isRestTimerRunning {
            inset += 88
        }
        return inset
    }

    private var inSessionCoachBar: some View {
        AskCoachBar(
            prompt: controller.isCoachThinking ? "Coach thinking" : "Ask coach",
            peekSnippet: ProactiveCoachPreferences.peekEnabled ? controller.coachPeekSnippet : nil,
            isLoading: controller.isCoachThinking
        ) {
            controller.isShowingCoachPrompt = true
        }
        .padding(.horizontal, HelmSpacing.screenGutter)
        .padding(.bottom, HelmSpacing.xs)
    }

    private var sessionActionBar: some View {
        VStack(spacing: HelmSpacing.sm) {
            Divider()
                .overlay(HelmColor.hairline)
                .padding(.top, HelmSpacing.md)

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
        }
        .padding(.bottom, HelmSpacing.sm)
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
                    Task { await controller.advanceNumpad() }
                }
            )
            .frame(height: HelmLayout.numpadHeight)
        }
        .background(HelmColor.canvas)
        .transition(.move(edge: .bottom))
    }
}

private struct SessionHeartRateChip: View {
    @Bindable private var watchCoordinator = WatchReadinessBootstrap.coordinator

    var body: some View {
        #if os(iOS)
        if watchCoordinator.isPaired {
            chipContent
        }
        #else
        chipContent
        #endif
    }

    private var chipContent: some View {
        HStack(spacing: HelmSpacing.sm) {
            Image(systemName: "heart.fill")
                .foregroundStyle(HelmColor.destructive)
            if let bpm = watchCoordinator.latestLiveHeartRateBPM {
                Text("\(bpm) BPM")
                    .helmType(.monoTag, color: HelmColor.fg)
            } else {
                Text("Waiting for heart rate…")
                    .helmType(.monoTag, color: HelmColor.fgSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, HelmSpacing.sm)
        .padding(.vertical, HelmSpacing.xs)
        .background(HelmColor.surfaceElevated, in: Capsule())
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

#Preview("Train empty") {
    ScrollView {
        HelmEmptyState(
            title: "No active session",
            message: "Start a workout or paste a plan from your coach.",
            icon: .train,
            actionTitle: "Start workout"
        ) {}
        .helmScreenPadding()
    }
    .helmTheme()
}

#Preview("Train loading") {
    ScrollView {
        HelmLoadingState(rowCount: 2)
            .helmScreenPadding()
    }
    .helmTheme()
}

#Preview("Train error") {
    ScrollView {
        HelmErrorState(
            title: "Session error",
            message: "Could not save the workout.",
            onRetry: {}
        )
        .helmScreenPadding()
    }
    .helmTheme()
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

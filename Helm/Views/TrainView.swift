import Core
import DesignSystem
import HealthKitIngest
import SwiftUI
import UIKit

struct TrainView: View {
    @Bindable private var controller = TrainBootstrap.sessionController
    @Bindable private var history = TrainBootstrap.historyController
    @Bindable private var importController = TrainBootstrap.importController
    @Bindable private var muscleVolumeStore = MuscleVolumeBootstrap.store
    @Bindable private var weekAheadStore = WeekAheadScheduleBootstrap.store
    @Bindable private var trainPreferences = TrainPreferences.shared
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.helmReduceMotion) private var reduceMotion

    @State private var isShowingImport = false
    @State private var didTrackInitialRestRemaining = false
    @State private var restEditorExerciseID: String?
    @State private var isShowingSavePrescriptionTemplate = false
    @State private var prescriptionTemplateName = ""
    @State private var didCopyPrescriptionExport = false

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
                // Launch recovery owns first restore; avoid double-recover races with rest-notification path.
                if TrainBootstrap.hasCompletedLaunchRecovery, controller.snapshot == nil {
                    await controller.recoverPersistedSession()
                } else if !TrainBootstrap.hasCompletedLaunchRecovery {
                    await controller.recoverPersistedSession()
                }
                history.refresh()
                muscleVolumeStore.refresh()
                await weekAheadStore.refresh()
            }
            .onChange(of: scenePhase) { _, newPhase in
                Task { await controller.handleScenePhase(newPhase) }
            }
            .onChange(of: WatchReadinessBootstrap.coordinator.isReachable) { _, reachable in
                controller.handleWatchReachabilityChange(isReachable: reachable)
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

                if controller.hasActiveSession {
                    bottomSessionChrome
                }
            }
            .helmScreenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(controller.hasActiveSession ? "" : "Train")
            .animation(
                HelmMotion.animation(HelmMotion.settleAnimation, reduceMotion: reduceMotion),
                value: controller.numpadTarget
            )
            .animation(
                HelmMotion.animation(HelmMotion.settleAnimation, reduceMotion: reduceMotion),
                value: controller.isRestTimerRunning
            )
        }
    }

    @ViewBuilder
    private var bottomSessionChrome: some View {
        let showRest = controller.isRestTimerRunning
            && controller.snapshot?.restTimer?.endsAt != nil
        let showCoach = controller.numpadTarget == nil && !controller.isReorderMode
        let showNumpad = controller.numpadTarget != nil

        VStack(spacing: 0) {
            if showRest || showCoach || showNumpad {
                LinearGradient(
                    colors: [
                        HelmColor.canvas.opacity(0),
                        HelmColor.canvas.opacity(0.85),
                        HelmColor.canvas
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: HelmLayout.trainBottomFogHeight)
                .allowsHitTesting(false)
            }

            VStack(spacing: HelmSpacing.xs) {
                if showRest,
                   let timer = controller.snapshot?.restTimer,
                   let endsAt = timer.endsAt {
                    RestTimerBanner(
                        endsAt: endsAt,
                        totalSeconds: controller.restTimerTotalSeconds(for: timer),
                        onSkip: {
                            Task { await controller.skipRest() }
                        },
                        onAdjust: { delta in
                            Task { await controller.adjustRestTimer(deltaSeconds: delta) }
                        },
                        onRemainingSecondsChange: { remaining in
                            handleRestTimerTick(remaining)
                        },
                        upNextName: controller.upNextExerciseName
                    )
                }

                if showCoach {
                    inSessionCoachBar
                }

                if showNumpad {
                    numpadOverlay
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity)
            .background(HelmColor.canvas)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var idleState: some View {
        ScrollView {
            HelmScreenStack {
                if let summary = controller.prescriptionSummary, !summary.exercises.isEmpty {
                    prescriptionIdleCard(summary)
                } else {
                    manualIdleCard
                }

                weekAheadSection

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
            .padding(.bottom, HelmLayout.trainScrollBottomInset)
        }
    }

    private func prescriptionIdleCard(_ summary: PrescribedSessionSummary) -> some View {
        VStack(alignment: .leading, spacing: HelmSpacing.lg) {
            if let staleMessage = controller.staleSessionMessage {
                StaleSessionBanner(message: staleMessage)
            }

            SessionDesignedCard(
                title: summary.title,
                summary: summary.summary,
                rationale: summary.rationale,
                onCoach: { controller.discussTodaysSession() },
                onRegenerate: {
                    Task { await controller.regenerateTodaysPrescription() }
                }
            ) {
                VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                    HStack(spacing: HelmSpacing.sm) {
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

                        Spacer(minLength: 0)
                    }

                    if summary.readinessAdjusted {
                        Text("Volume trimmed for readiness")
                            .helmType(.monoTag, color: HelmColor.depleted)
                    }

                    SessionExercisePreviewList(
                        exercises: summary.exercises.map(\.displayName)
                    )

                    Text("\(summary.totalSets) total sets")
                        .helmType(.body, color: HelmColor.fgSecondary)
                }
            }

            Button("Start today's session") {
                Task { await controller.startTodaysPrescription() }
            }
            .buttonStyle(.helmPrimary)

            Button("Save as template") {
                prescriptionTemplateName = summary.title
                isShowingSavePrescriptionTemplate = true
            }
            .buttonStyle(.helmSecondary)

            Button("Export") {
                Task {
                    if let text = await controller.exportPrescriptionText() {
                        UIPasteboard.general.string = text
                        didCopyPrescriptionExport = true
                    }
                }
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
        .alert("Copied", isPresented: $didCopyPrescriptionExport) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Prescription copied for Gemini verification.")
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

    private var weekAheadSection: some View {
        WeekAheadScheduleSection(store: weekAheadStore)
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
            coachingCue: controller.coachingCue(for: exercise.exerciseID),
            restSeconds: exercise.targetRestSeconds ?? 90,
            isReorderMode: controller.isReorderMode,
            previousLookup: { set in
                controller.previousFor(set: set, exerciseID: exercise.exerciseID)
            },
            activeField: controller.numpadTarget,
            numpadSelectAll: controller.numpadSelectAll,
            validationMessage: controller.numpadValidationError,
            advisoryMessage: { setID in controller.rirAdvisory(forSetID: setID) },
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
            onOpenHistory: {
                controller.openExerciseHistory(sessionExerciseID: exercise.id)
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
                        TrainSessionHeaderView(
                            startedAt: snapshot.session.startedAt,
                            progress: TrainSessionProgress.from(snapshot: snapshot),
                            heartRateBPM: WatchReadinessBootstrap.coordinator.canDriveWatchCompanion
                                ? WatchReadinessBootstrap.coordinator.latestLiveHeartRateBPM
                                : nil
                        )

                        if let notice = controller.watchCompanionNotice {
                            Button {
                                if notice.contains("retry") || notice.contains("Wake") || notice.contains("wake") {
                                    controller.retryWatchCompanionLaunch()
                                } else {
                                    controller.dismissWatchCompanionNotice()
                                }
                            } label: {
                                Text(notice)
                                    .helmType(.body, color: HelmColor.fgSecondary)
                                    .padding(.horizontal, HelmSpacing.xs)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(notice)
                        }

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
                    .frame(maxWidth: .infinity)
                }
                .animation(
                    HelmMotion.animation(HelmMotion.settleAnimation, reduceMotion: reduceMotion),
                    value: controller.adjustmentBanner
                )
                .animation(
                    HelmMotion.animation(HelmMotion.settleAnimation, reduceMotion: reduceMotion),
                    value: controller.numpadTarget
                )
            }

            HelmCoachApplyWave(isActive: $controller.showCoachApplyWave)
        }
    }

    private func handleRestTimerTick(_ remaining: Int) {
        // Pass 0 at expiry so restDone policy fires (nil was skipping the bell).
        let current: Int? = remaining
        if !didTrackInitialRestRemaining {
            didTrackInitialRestRemaining = true
            controller.handleRestRemainingSecondsChange(remaining > 0 ? remaining : 0)
            return
        }
        controller.handleRestRemainingSecondsChange(current)
        if remaining == 0 {
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
            inset += HelmLayout.trainRestBannerScrollInset
        }
        return inset
    }

    private var inSessionCoachBar: some View {
        let restTimer = controller.snapshot?.restTimer
        let coachBar = AskCoachBar(
            prompt: controller.isCoachThinking ? "Coach thinking" : "Ask coach",
            peekSnippet: ProactiveCoachPreferences.peekEnabled ? controller.coachPeekSnippet : nil,
            isLoading: controller.isCoachThinking
        ) {
            controller.isShowingCoachPrompt = true
        }

        return Group {
            if trainPreferences.pawelModeEnabled {
                HStack(spacing: HelmSpacing.xs) {
                    coachBar
                        .layoutPriority(1)

                    PawelTimerPill(
                        isRunning: controller.isRestTimerRunning,
                        endsAt: restTimer?.endsAt
                    ) {
                        controller.isShowingPawelTimer = true
                    }
                    .frame(minWidth: 88, maxWidth: 96)
                }
                .padding(.horizontal, HelmSpacing.screenGutter)
                .padding(.bottom, HelmSpacing.xs)
            } else {
                coachBar
                    .padding(.horizontal, HelmSpacing.screenGutter)
                    .padding(.bottom, HelmSpacing.xs)
            }
        }
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
        let isRPE = controller.numpadTarget?.field == .rpe

        return VStack(spacing: 0) {
            Button {
                Task { await controller.dismissNumpad() }
            } label: {
                Image(systemName: "chevron.compact.down")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(HelmColor.fgSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, HelmSpacing.sm)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss keyboard")
            .simultaneousGesture(
                DragGesture(minimumDistance: 12)
                    .onEnded { value in
                        guard value.translation.height > 24,
                              value.predictedEndTranslation.height > 40 else { return }
                        Task { await controller.dismissNumpad() }
                    }
            )

            if isRPE {
                HelmRPESlider(value: $controller.numpadDraftRPE)

                Button("Done") {
                    Task { await controller.completeSetFromRPEDone() }
                }
                .buttonStyle(.helmPrimary)
                .padding(.horizontal, HelmSpacing.sm)
                .padding(.bottom, HelmSpacing.sm)
            } else {
                if !controller.numpadWorkingText.isEmpty || controller.numpadSelectAll {
                    Text(controller.numpadWorkingText.isEmpty ? "0" : controller.numpadWorkingText)
                        .helmType(.bigNumber)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, HelmSpacing.sm)
                        .background(HelmColor.surface)
                }

                HelmNumpad(
                    allowsDecimal: controller.numpadTarget?.field != .reps,
                    onDigit: { controller.appendNumpadDigit($0) },
                    onBackspace: { controller.backspaceNumpad() }
                )
                .frame(height: HelmNumpadMetrics.preferredHeight(showsAction: false))
            }
        }
        .background(HelmColor.canvas)
        .transition(.move(edge: .bottom))
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

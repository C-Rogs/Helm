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
    @ObservedObject private var spotify = SpotifyAppRemoteService.shared
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.helmReduceMotion) private var reduceMotion

    @State private var isShowingImport = false
    @State private var didTrackInitialRestRemaining = false
    @State private var restEditorExerciseID: String?
    @State private var isShowingSavePrescriptionTemplate = false
    @State private var prescriptionTemplateName = ""
    @State private var didCopyPrescriptionExport = false
    @State private var measuredChromeHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0
    @State private var suppressChromeAnimations = false
    @State private var isShowingSessionLog = false

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
                await AppTabRouter.shared.preferChromeOverContentLoad()
                guard !Task.isCancelled else { return }
                history.refresh()
                muscleVolumeStore.refresh()
                await weekAheadStore.refresh()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    // Clear any mid-wave state after returning from background.
                    CoachApplyMomentStore.shared.isActive = false
                    suppressChromeAnimations = true
                    DispatchQueue.main.async {
                        suppressChromeAnimations = false
                    }
                }
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

                if controller.hasActiveSession, controller.numpadTarget != nil {
                    // No full-screen overlay. Field hops (weight -> reps -> RPE)
                    // must pass through to the session scroll below. Dismiss via
                    // chevron or swipe-down on the pad itself.
                }

                if controller.hasActiveSession {
                    bottomSessionChrome
                }
            }
            .onPreferenceChange(TrainBottomChromeHeightKey.self) { height in
                measuredChromeHeight = height
            }
            .helmScreenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(controller.hasActiveSession ? "" : "Train")
        }
    }

    @ViewBuilder
    private var bottomSessionChrome: some View {
        let showRest = controller.isRestTimerRunning
            && controller.snapshot?.restTimer?.endsAt != nil
        let showCoach = controller.numpadTarget == nil && !controller.isReorderMode
        let showNumpad = controller.numpadTarget != nil

        VStack(spacing: 0) {
            VStack(spacing: HelmSpacing.xs) {
                if showRest,
                   let timer = controller.snapshot?.restTimer,
                   let endsAt = timer.endsAt {
                    if showNumpad {
                        // Rest must stay glanceable while pre-logging the next set;
                        // the full banner would stack too tall over the pad.
                        CompactRestPill(
                            endsAt: endsAt,
                            totalSeconds: controller.restTimerTotalSeconds(for: timer),
                            onRemainingSecondsChange: { remaining in
                                handleRestTimerTick(remaining)
                            }
                        )
                        .geometryGroup()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        RestTimerBanner(
                            endsAt: endsAt,
                            totalSeconds: controller.restTimerTotalSeconds(for: timer),
                            onSkip: {
                                Task { @MainActor in await controller.skipRest() }
                            },
                            onAdjust: { delta in
                                Task { @MainActor in await controller.adjustRestTimer(deltaSeconds: delta) }
                            },
                            onRemainingSecondsChange: { remaining in
                                handleRestTimerTick(remaining)
                            },
                            upNextName: controller.upNextExerciseName
                        )
                        .geometryGroup()
                        .transition(.opacity)
                    }
                }

                if showCoach {
                    inSessionCoachBar
                }

                if showNumpad {
                    numpadOverlay
                }
            }
            .frame(maxWidth: .infinity)
            .background(.regularMaterial, in: Rectangle())
            // Numpad chrome uses standard (not settle) so rest banner layout
            // lifts in lockstep with the pad. Settle left the dock behind.
            .animation(
                suppressChromeAnimations
                    ? nil
                    : HelmMotion.animation(HelmMotion.standardAnimation, reduceMotion: reduceMotion),
                value: controller.numpadTarget
            )
            .animation(
                suppressChromeAnimations
                    ? nil
                    : HelmMotion.animation(HelmMotion.standardAnimation, reduceMotion: reduceMotion),
                value: controller.isRestTimerRunning
            )
        }
        .background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: TrainBottomChromeHeightKey.self,
                    value: geometry.size.height
                )
            }
        }
        .transaction { transaction in
            if suppressChromeAnimations {
                transaction.animation = nil
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var idleState: some View {
        ScrollView {
            HelmScreenStack {
                if let summary = controller.prescriptionSummary, !summary.exercises.isEmpty {
                    prescriptionIdleCard(summary)
                } else {
                    genericIdleCard(rest: PlanBootstrap.prescriptionService.state.restDay)
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

                WorkoutHistoryRecentSection(history: history)
            }
            .helmScreenPadding()
            .padding(.bottom, HelmLayout.trainScrollBottomInset)
        }
    }

    private func prescriptionIdleCard(_ summary: PrescribedSessionSummary) -> some View {
        VStack(alignment: .leading, spacing: HelmSpacing.lg) {
            SessionDesignedCard(
                title: summary.title,
                summary: summary.summary,
                rationale: summary.rationale,
                leadingChipTitle: "Discuss",
                onLeadingChip: { controller.discussTodaysSession() },
                onRegenerate: {
                    Task {
                        await controller.regenerateTodaysPrescription()
                        await weekAheadStore.refresh()
                    }
                }
            ) {
                VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                    if summary.readinessAdjusted {
                        Text("Volume trimmed for readiness")
                            .helmType(.monoTag, color: HelmColor.depleted)
                    }

                    SessionExercisePreviewList(
                        exercises: summary.exercises.map(\.displayName)
                    )
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
                Task { @MainActor in
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

    private func genericIdleCard(rest: RestDaySummary?) -> some View {
        VStack(spacing: HelmSpacing.lg) {
            if let rest {
                SessionDesignedCard(
                    title: rest.title,
                    summary: rest.summary,
                    rationale: rest.rationale,
                    leadingChipTitle: "Discuss",
                    onLeadingChip: { controller.discussTodaysSession() }
                ) {
                    Text("Check week ahead for the next training day.")
                        .helmType(.body, color: HelmColor.fgSecondary)
                }
            } else {
                HelmEmptyState(
                    title: "No active session",
                    message: "Start a workout or paste a plan from your coach.",
                    icon: .train,
                    actionTitle: "Start workout"
                ) {
                    Task { await controller.startWorkout() }
                }
            }

            Button(rest != nil ? "Empty workout" : "Paste workout plan") {
                if rest != nil {
                    Task { await controller.startWorkout() }
                } else {
                    isShowingImport = true
                }
            }
            .buttonStyle(.helmSecondary)

            if rest != nil {
                Button("Paste workout plan") {
                    isShowingImport = true
                }
                .buttonStyle(.helmSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, HelmSpacing.md)
    }

    private var weekAheadSection: some View {
        WeekAheadScheduleSection(store: weekAheadStore) {
            Task {
                await controller.regenerateTodaysPrescription()
                await weekAheadStore.refresh()
            }
        }
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
            blockerShakeToken: { setID in controller.blockerShakeToken(forSetID: setID) },
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
                Task { @MainActor in await controller.cycleSetType(setID: setID) }
            },
            onCompleteSet: { sessionExerciseID, setID in
                Task { @MainActor in
                    await controller.completeSet(
                        sessionExerciseID: sessionExerciseID,
                        setID: setID
                    )
                }
            },
            onAddSet: {
                Task { @MainActor in await controller.addSet(sessionExerciseID: exercise.id) }
            },
            onRemoveSet: {
                Task { @MainActor in await controller.removeSet(sessionExerciseID: exercise.id) }
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
            canMoveUp: controller.canMoveExerciseUp(sessionExerciseID: exercise.id),
            canMoveDown: controller.canMoveExerciseDown(sessionExerciseID: exercise.id),
            onMoveUp: {
                controller.moveExerciseUpInDraft(sessionExerciseID: exercise.id)
            },
            onMoveDown: {
                controller.moveExerciseDownInDraft(sessionExerciseID: exercise.id)
            }
        )
    }

    private func activeSessionView(_ snapshot: ActiveSessionSnapshot) -> some View {
        ZStack {
            VStack(spacing: 0) {
                if trainPreferences.cardLoggingModeEnabled {
                    cardLoggingContent(snapshot)
                } else {
                    tableLoggingContent(snapshot)
                }
            }

            // Coach apply wave mounts at AppRootView for app-wide AI applies.
        }
        .sheet(isPresented: $isShowingSessionLog) {
            FocusSessionLogSheet(
                exercises: controller.exercisesForDisplay(),
                displayName: { controller.displayName(for: $0) },
                onUndoSet: { sessionExerciseID, setID in
                    Task { @MainActor in
                        await controller.completeSet(
                            sessionExerciseID: sessionExerciseID,
                            setID: setID
                        )
                    }
                }
            )
        }
    }

    private func cardLoggingContent(_ snapshot: ActiveSessionSnapshot) -> some View {
        VStack(spacing: 0) {
            // Header with mode toggle
            HStack {
                TrainSessionHeaderView(
                    startedAt: snapshot.session.startedAt,
                    progress: TrainSessionProgress.from(snapshot: snapshot),
                    watchLinkStatus: WatchCompanionLinkStatus.resolve(
                        canDriveWatch: WatchReadinessBootstrap.coordinator.canDriveWatchCompanion,
                        phoneHRActive: WatchReadinessBootstrap.coordinator.isPhoneHeartRateSessionActive,
                        liveBPM: WatchReadinessBootstrap.coordinator.liveHeartRateBPMForDisplay
                    )
                )

                Spacer()

                Button {
                    trainPreferences.cardLoggingModeEnabled = false
                } label: {
                    Image(systemName: "tablecells")
                        .font(.body)
                        .foregroundStyle(HelmColor.fgSecondary)
                        .frame(width: HelmLayout.minTapTarget, height: HelmLayout.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.helmPressable)
                .accessibilityLabel("Switch to table view")
            }
            .padding(.horizontal, HelmSpacing.md)

            if let banner = controller.adjustmentBanner {
                AdjustmentBanner(
                    fromLabel: banner.fromLabel,
                    toLabel: banner.toLabel,
                    reason: banner.reason
                ) {
                    Task { await controller.undoLastAdjustment() }
                }
                .padding(.horizontal, HelmSpacing.md)
            }

            if snapshot.session.exercises.isEmpty {
                VStack {
                    Spacer()
                    Text("Add your first exercise to begin logging sets.")
                        .helmType(.body, color: HelmColor.fgSecondary)
                    Button {
                        controller.isShowingExercisePicker = true
                    } label: {
                        Label("Add exercise", helmIcon: .plus, context: .inline)
                    }
                    .buttonStyle(.helmSecondary)
                    Spacer()
                }
            } else {
                FocusCardLoggingView(
                    exercises: Array(controller.exercisesForDisplay().prefix(16)),
                    controller: controller,
                    isShowingSessionLog: $isShowingSessionLog
                )

                if !controller.isReorderMode {
                    HStack(spacing: HelmSpacing.sm) {
                        Button {
                            controller.isShowingExercisePicker = true
                        } label: {
                            Label("Add exercise", helmIcon: .plus, context: .inline)
                        }
                        .buttonStyle(.helmSecondary)

                        Spacer()

                        sessionActionBar
                    }
                    .padding(.horizontal, HelmSpacing.md)
                    .padding(.top, HelmSpacing.sm)
                }
            }

            Spacer(minLength: bottomContentInset)
        }
    }

    private func tableLoggingContent(_ snapshot: ActiveSessionSnapshot) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: HelmSpacing.md) {
                    HStack {
                        TrainSessionHeaderView(
                            startedAt: snapshot.session.startedAt,
                            progress: TrainSessionProgress.from(snapshot: snapshot),
                            watchLinkStatus: WatchCompanionLinkStatus.resolve(
                                canDriveWatch: WatchReadinessBootstrap.coordinator.canDriveWatchCompanion,
                                phoneHRActive: WatchReadinessBootstrap.coordinator.isPhoneHeartRateSessionActive,
                                liveBPM: WatchReadinessBootstrap.coordinator.liveHeartRateBPMForDisplay
                            )
                        )

                        Spacer()

                        Button {
                            trainPreferences.cardLoggingModeEnabled = true
                        } label: {
                            Image(systemName: "rectangle.grid.1x2")
                                .font(.body)
                                .foregroundStyle(HelmColor.fgSecondary)
                                .frame(width: HelmLayout.minTapTarget, height: HelmLayout.minTapTarget)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.helmPressable)
                        .accessibilityLabel("Switch to card view")
                    }
                    .padding(.horizontal, HelmSpacing.xs)

                    if spotify.isAuthorized, !spotify.isConnected {
                        Button {
                            spotify.wakeSpotifyAndConnect()
                        } label: {
                            HStack(spacing: HelmSpacing.xxs) {
                                Image(systemName: "music.note")
                                    .font(.caption)
                                Text("Open Spotify")
                                    .helmType(.monoTag, color: HelmColor.fgSecondary)
                            }
                            .padding(.horizontal, HelmSpacing.xs)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open Spotify")
                        .accessibilityHint("Switches to Spotify so Helm can read now playing")
                    }

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
                    .animation(
                        HelmMotion.animation(
                            HelmMotion.settleAnimation,
                            reduceMotion: reduceMotion
                        ),
                        value: controller.reorderDraftIDs
                    )

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
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: TrainViewportHeightKey.self,
                        value: geometry.size.height
                    )
                }
            }
            .onPreferenceChange(TrainViewportHeightKey.self) { height in
                viewportHeight = height
            }
            .animation(
                HelmMotion.animation(HelmMotion.settleAnimation, reduceMotion: reduceMotion),
                value: controller.adjustmentBanner
            )
            .onChange(of: controller.numpadTarget) { _, target in
                guard let setID = target?.setID else { return }
                scheduleScrollToFocusedSet(
                    proxy: proxy,
                    setID: setID,
                    viewportHeight: viewportHeight
                )
            }
            .onChange(of: measuredChromeHeight) { _, _ in
                guard let setID = controller.numpadTarget?.setID else { return }
                scheduleScrollToFocusedSet(
                    proxy: proxy,
                    setID: setID,
                    viewportHeight: viewportHeight
                )
            }
        }
    }

    private func scheduleScrollToFocusedSet(
        proxy: ScrollViewProxy,
        setID: String,
        viewportHeight: CGFloat
    ) {
        DispatchQueue.main.async {
            scrollToFocusedSet(
                proxy: proxy,
                setID: setID,
                viewportHeight: viewportHeight
            )
        }
    }

    private func scrollToFocusedSet(
        proxy: ScrollViewProxy,
        setID: String,
        viewportHeight: CGFloat
    ) {
        HapticEngine.shared.play(.selection)
        let anchor = focusedSetScrollAnchor(
            chromeHeight: measuredChromeHeight,
            viewportHeight: viewportHeight
        )
        withAnimation(
            HelmMotion.animation(HelmMotion.settleAnimation, reduceMotion: reduceMotion)
        ) {
            proxy.scrollTo(setID, anchor: anchor)
        }
    }

    private func focusedSetScrollAnchor(chromeHeight: CGFloat, viewportHeight: CGFloat) -> UnitPoint {
        guard viewportHeight > 0, chromeHeight > 0 else {
            return UnitPoint(x: 0.5, y: 0.35)
        }
        let visibleFraction = max(0.2, 1 - (chromeHeight / viewportHeight))
        let y = min(0.5, max(0.15, visibleFraction * 0.5))
        return UnitPoint(x: 0.5, y: y)
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
        // Rest-monitor owns expiry reconcile. Do not spawn a bare Task here; that raced
        // the monitor and mutated SwiftUI off the main thread after await.
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
        if measuredChromeHeight > 0 {
            return measuredChromeHeight + HelmSpacing.sm
        }

        if controller.numpadTarget != nil {
            if controller.numpadTarget?.field == .rpe {
                return HelmLayout.trainScrollBottomInsetWithRPE
            }
            return HelmLayout.trainScrollBottomInsetWithNumpad
        }

        var inset = HelmLayout.trainScrollBottomInset
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
            if trainPreferences.manualRestTimerEnabled {
                HStack(spacing: HelmSpacing.xs) {
                    coachBar
                        .layoutPriority(1)

                    ManualRestTimerPill(
                        isRunning: controller.isRestTimerRunning,
                        endsAt: restTimer?.endsAt
                    ) {
                        controller.openManualRestTimer(expanded: controller.isRestTimerRunning)
                    }
                    .fixedSize(horizontal: true, vertical: false)
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
                .disabled(controller.isFinishingWorkout)

                HelmActionButton(
                    "Finish workout",
                    phase: controller.isFinishingWorkout ? .loading : .idle,
                    successTitle: "Done"
                ) {
                    controller.isShowingFinishConfirmation = true
                }
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
                if controller.numpadTarget?.field == .weight {
                    weightIncrementChips
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
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// Plate-math shortcuts: smallest common gym increments so 80 -> 82.5 is one
    /// tap instead of a four-digit retype.
    private var weightIncrementChips: some View {
        HStack(spacing: HelmSpacing.xs) {
            ForEach([-2.5, -1.25, 1.25, 2.5], id: \.self) { delta in
                Button {
                    controller.adjustNumpadValue(by: delta)
                } label: {
                    Text(incrementLabel(delta))
                        .helmType(.number, color: HelmColor.fg)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, HelmSpacing.xs)
                        .background(HelmColor.surfaceElevated, in: RoundedRectangle(cornerRadius: HelmRadius.sm))
                }
                .buttonStyle(.helmPressable)
                .accessibilityLabel("\(delta > 0 ? "Add" : "Subtract") \(incrementLabel(abs(delta))) kilograms")
            }
        }
        .padding(.horizontal, HelmSpacing.sm)
        .padding(.bottom, HelmSpacing.xs)
    }

    private func incrementLabel(_ delta: Double) -> String {
        let magnitude = abs(delta)
        let formatted = magnitude.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", magnitude)
            : String(format: "%.2f", magnitude).replacingOccurrences(of: "50", with: "5")
        return delta < 0 ? "−\(formatted)" : "+\(formatted)"
    }
}

/// Single-line rest countdown shown while the numpad owns the bottom chrome.
/// Progress fill plus mm:ss only; full controls return when the pad dismisses.
private struct CompactRestPill: View {
    let endsAt: Date
    let totalSeconds: Int
    var onRemainingSecondsChange: ((Int) -> Void)?

    @Environment(\.helmReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int(endsAt.timeIntervalSince(context.date).rounded(.down)))
            let elapsedFraction = totalSeconds > 0
                ? 1 - (Double(remaining) / Double(totalSeconds))
                : 1

            HStack(spacing: HelmSpacing.sm) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(HelmColor.gaugeTrack.opacity(0.5))
                        Capsule()
                            .fill(HelmColor.accent)
                            .frame(width: elapsedFraction > 0 ? max(6, geometry.size.width * elapsedFraction) : 0)
                            .transaction(value: elapsedFraction) { transaction in
                                transaction.animation = reduceMotion ? nil : .linear(duration: 1)
                            }
                    }
                }
                .frame(height: 4)

                Text(RestTimerFormatting.mmss(remaining))
                    .helmType(.number, color: HelmColor.fg)
                    .helmNumericRoll(value: remaining)
            }
            .padding(.horizontal, HelmSpacing.sm)
            .padding(.vertical, HelmSpacing.xxs)
            .onChange(of: remaining) { _, newValue in
                onRemainingSecondsChange?(newValue)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Rest remaining \(RestTimerFormatting.mmss(remaining))")
        }
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

private struct TrainBottomChromeHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct TrainViewportHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

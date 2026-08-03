import Core
import CoachLLM
import DesignSystem
import Diagnostics
import Foundation
import HealthKitIngest
import Observation
import Persistence
import PlanKit
import ReadinessKit
import SwiftUI

enum NumpadFieldKind: Hashable, Sendable {
    case weight
    case reps
    case rpe
}

struct InSessionCoachMessage: Identifiable, Equatable, Sendable {
    enum Role: Sendable, Equatable {
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    let text: String

    init(id: UUID = UUID(), role: Role, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}

struct NumpadTarget: Hashable, Sendable {
    let setID: String
    let sessionExerciseID: String
    let field: NumpadFieldKind
}

@MainActor
@Observable
final class TrainSessionController {
    let store: ActiveSessionStore
    let sideEffects: WorkoutSessionSideEffects

    private let persistence: PersistenceStore
    private let prescriptionService: PrescriptionService
    private let inSessionCoach: InSessionCoachService
    private let preStartCoach: PreStartCoachService
    private let providerPreferences: ProviderPreferencesStore

    private(set) var exerciseSummaries: [String: ExerciseSummary] = [:]
    private(set) var previousPerformance: [String: PreviousPerformance] = [:]
    private(set) var exerciseTargets: [String: String] = [:]
    private(set) var prescriptionSummary: PrescribedSessionSummary?
    private(set) var staleSessionMessage: String?
    private(set) var lastFinishedPersonalRecords: [DetectedPersonalRecord] = []
    private(set) var lastSetPersonalRecords: [DetectedPersonalRecord] = []
    private(set) var sessionPRRecordsBySetID: [String: [DetectedPersonalRecord]] = [:]
    private(set) var encouragementGlyphBySetID: [String: EncouragementGlyph] = [:]
    private(set) var rirAdvisoryBySetID: [String: String] = [:]
    private(set) var historicalBestE1RM: [String: Mass] = [:]
    private(set) var prCelebrationSetID: String?
    private(set) var lastFinishSummary: WorkoutFinishSummary?

    var numpadTarget: NumpadTarget?
    var numpadWorkingText = ""
    var numpadSelectAll = false
    var numpadDraftRPE = 8.0

    var isShowingExercisePicker = false
    var isShowingFinishConfirmation = false
    var isShowingDiscardConfirmation = false
    var pendingDeleteExerciseID: String? {
        pendingExerciseRemoval.pendingID
    }
    private var pendingExerciseRemoval = PendingExerciseRemoval()
    var numpadValidationError: String?
    var numpadShakeToken = 0
    var isShowingFinishSummary = false
    var isShowingPersonalRecords = false
    var errorMessage: String?

    var coachPromptText = ""
    var isShowingCoachPrompt = false
    var isShowingPawelTimer = false
    var historyExerciseSessionID: String?
    private(set) var coachMessages: [InSessionCoachMessage] = []
    private(set) var pendingCoachProposal: CoachSessionProposal?
    private(set) var isCoachThinking = false
    private(set) var coachTurnError: String?
    private(set) var lastFailedCoachMessage: String?
    var showCoachApplyWave = false
    private(set) var lastCoachRequestID: UUID?
    private(set) var adjustmentBanner: SessionAdjustmentBannerModel?
    private(set) var proactiveCoachBanner: String?
    private(set) var coachPeekSnippet: String?
    private(set) var watchCompanionNotice: String?
    /// True when Watch delivered live HR this session; prefer Watch HKWorkout, skip phone energy estimate.
    private(set) var watchCompanionDeliveredHeartRate = false

    private var didSurfaceRestOverrunProactive = false
    private var firedMilestoneQuartiles: Set<Int> = []
    private var watchLiveConfirmTask: Task<Void, Never>?
    private var didRelaunchWatchForReachability = false

    private var coachThread = CoachThreadState.empty

    private var excludedExerciseIDs: Set<String> = []
    private var undoStack: [AppliedSessionAdjustment] = []

    private var previousRestRemaining: Int?
    private var wasRestRunningOnBackground = false
    private var trackedRestTimerID: String?
    private let prescriptionAutoStartStore: PrescriptionAutoStartStore
    private let trainPreferences: TrainPreferences

    private var sessionPersonalRecordKeys: Set<String> = []
    private var lastEncouragementGlyph: EncouragementGlyph?
    private var sessionNoteSaveTask: Task<Void, Never>?
    private var coachMessageTask: Task<Void, Never>?
    private var restTimerMonitorTask: Task<Void, Never>?
    private var heartRateSampleTask: Task<Void, Never>?
    private var sessionHeartRateBuffer = SessionHeartRateBuffer()
    private var sessionNoteIsDirty = false
    private var lastSyncedRestRemaining: Int?
    private var lastLiveActivitySyncDate: Date?

    var sessionNoteText = ""
    private(set) var sessionNoteSavedConfirmation = false
    var isReorderMode = false
    private(set) var reorderDraftIDs: [String] = []

    init(
        store: ActiveSessionStore,
        persistence: PersistenceStore,
        sideEffects: WorkoutSessionSideEffects,
        prescriptionService: PrescriptionService,
        inSessionCoach: InSessionCoachService? = nil,
        preStartCoach: PreStartCoachService? = nil,
        providerPreferences: ProviderPreferencesStore = ProviderPreferencesStore(),
        prescriptionAutoStartStore: PrescriptionAutoStartStore = PrescriptionAutoStartStore(),
        trainPreferences: TrainPreferences = .shared
    ) {
        self.store = store
        self.persistence = persistence
        self.sideEffects = sideEffects
        self.prescriptionService = prescriptionService
        self.inSessionCoach = inSessionCoach ?? InSessionCoachService(persistence: persistence)
        self.preStartCoach = preStartCoach ?? PreStartCoachService(persistence: persistence)
        self.providerPreferences = providerPreferences
        self.prescriptionAutoStartStore = prescriptionAutoStartStore
        self.trainPreferences = trainPreferences
    }

    var snapshot: ActiveSessionSnapshot? {
        store.snapshot
    }

    var hasActiveSession: Bool {
        store.hasActiveSession
    }

    var isRestTimerRunning: Bool {
        snapshot?.restTimer?.phase == .running
    }

    func restTimerTotalSeconds(for timer: RestTimer) -> Int {
        if let started = timer.startedAt, let ends = timer.endsAt {
            return max(1, Int(ends.timeIntervalSince(started).rounded()))
        }
        if timer.defaultDurationSeconds > 0 {
            return timer.defaultDurationSeconds
        }
        if let ends = timer.endsAt {
            return max(1, Int(ends.timeIntervalSince(Date()).rounded()))
        }
        return 90
    }

    /// Reloads the persisted active session from the database (kill-recover, tab return).
    func recoverPersistedSession() async {
        await store.recover()
        await refreshMetadata()
        syncSessionNoteFromSnapshot()
    }

    /// App-launch recovery: restore an in-progress session or show today's prescription on the idle card.
    func recoverOnLaunch() async {
        await recoverPersistedSession()
        await abandonUntouchedPrescriptionIfNeeded()
        if let snapshot = store.snapshot {
            await sideEffects.onSessionStarted(snapshot)
            activateWatchCompanionAfterSessionStart()
        } else {
            await refreshPrescriptionState()
        }
        await sideEffects.reconcileLiveActivitiesOnLaunch(hasActiveSession: store.snapshot != nil)
    }

    func refreshPrescriptionState() async {
        let readiness = ReadinessBootstrap.readinessService.state.score
        await prescriptionService.refresh(readiness: readiness)
        prescriptionSummary = prescriptionService.state.summary
        evaluatePrescriptionStaleness(readiness: readiness)
    }

    func regenerateTodaysPrescription() async {
        let day = todayHelmDay()
        PrescriptionDayStore.clear(for: day)
        let readiness = ReadinessBootstrap.readinessService.state.score
        await prescriptionService.refresh(readiness: readiness)
        prescriptionSummary = prescriptionService.state.summary
        recordPrescriptionFingerprint(readiness: readiness)
        staleSessionMessage = nil
    }

    func discussTodaysSession() {
        guard !hasActiveSession else {
            isShowingCoachPrompt = true
            return
        }
        isShowingCoachPrompt = true
        coachMessageTask?.cancel()
        coachMessageTask = Task { @MainActor in
            await loadPreStartCoachIntro()
        }
    }

    func exportPrescriptionText() async -> String? {
        do {
            let readiness = ReadinessBootstrap.readinessService.state.score
            let prescription = try await prescriptionService.todaysPrescription(readiness: readiness)
            guard !prescription.exercises.isEmpty else { return nil }
            let names = try persistence.exercises.displayNames(for: prescription.exercises.map(\.exerciseID))
            return WorkoutExportFormatter.formatPrescriptionForClipboard(
                prescription: prescription,
                displayNames: names
            )
        } catch {
            return nil
        }
    }

    private func loadPreStartCoachIntro() async {
        guard let summary = prescriptionSummary else { return }
        isCoachThinking = true
        defer { isCoachThinking = false }

        let brief = SessionDesignBrief(
            title: summary.title,
            summary: summary.summary,
            rationale: summary.rationale,
            splitKind: summary.splitKind
        )

        do {
            let profile = try persistence.memoryProfile.load()
            let endDay = todayHelmDay()
            let context = try await CoachContextAssembler.assemble(from: persistence, endingAt: endDay)
            let provider = ProviderRegistry.shared.provider(for: providerPreferences.selectedProvider)
            let intro = try await preStartCoach.generateIntro(
                brief: brief,
                summary: summary,
                provider: provider,
                profile: profile,
                context: context
            )
            coachMessages = [InSessionCoachMessage(role: .assistant, text: intro.text)]
            coachThread = CoachThreadState(messages: [CoachMessage(role: .assistant, text: intro.text)])
            coachTurnError = nil
            CoachDiagnosticsStore.shared.clear()
        } catch {
            coachTurnError = CoachUserFacingError.message(for: error)
            coachMessages = []
            coachThread = .empty
            CoachDiagnosticsStore.shared.recordFailure(surface: "preStartIntro", error: error)
            Task {
                await DiagnosticsLog.shared.capture(
                    error: error,
                    category: .coachLLM,
                    message: "Pre-start coach intro failed"
                )
            }
        }
    }

    func saveTodaysPrescriptionAsTemplate(name: String) async {
        do {
            let readiness = ReadinessBootstrap.readinessService.state.score
            let prescription = try await prescriptionService.todaysPrescription(readiness: readiness)
            guard !prescription.exercises.isEmpty else {
                errorMessage = "No prescription available to save."
                return
            }
            _ = try persistence.workoutTemplates.createFromPrescription(
                prescription,
                name: name
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setCoachPeekSnippet(_ snippet: String) {
        coachPeekSnippet = snippet
    }

    func setProactiveCoachBanner(_ message: String) {
        proactiveCoachBanner = message
    }

    func dismissProactiveCoachBanner() {
        proactiveCoachBanner = nil
    }

    func insertProactiveCoachMessage(_ message: String) {
        coachMessages.append(InSessionCoachMessage(role: .assistant, text: message))
        coachThread.messages.append(CoachMessage(role: .assistant, text: message))
    }

    func handleRestExpiredProactiveCoach() {
        // Rest-over feedback is haptic/sound only (F-DT8.5); no proactive coach surfacing.
    }

    private func evaluatePrescriptionStaleness(readiness: ReadinessScore?) {
        guard prescriptionSummary != nil else {
            staleSessionMessage = nil
            return
        }
        let day = todayHelmDay()
        let fingerprint = prescriptionFingerprint(readiness: readiness)
        if PrescriptionStaleTracker.isStale(currentFingerprint: fingerprint, day: day) {
            staleSessionMessage = PrescriptionStaleTracker.staleMessage(readinessScore: readiness?.score)
        } else {
            staleSessionMessage = nil
            let hasBaseline = UserDefaults.standard.string(forKey: "helm.prescription.stale.day") == day.formatted
                && UserDefaults.standard.string(forKey: "helm.prescription.stale.fingerprint") != nil
            if !hasBaseline {
                PrescriptionStaleTracker.recordFingerprint(fingerprint, for: day)
            }
        }
    }

    private func recordPrescriptionFingerprint(readiness: ReadinessScore?) {
        PrescriptionStaleTracker.recordFingerprint(
            prescriptionFingerprint(readiness: readiness),
            for: todayHelmDay()
        )
    }

    private func prescriptionFingerprint(readiness: ReadinessScore?) -> String {
        let summary = prescriptionSummary
        return [
            todayHelmDay().formatted,
            readiness.map { String($0.score) } ?? "nil",
            summary.map { "\($0.phase)-\($0.totalSets)-\($0.exercises.count)-\($0.readinessAdjusted)" } ?? "none"
        ].joined(separator: "|")
    }

    func startWorkout() async {
        do {
            exerciseTargets = [:]
            resetCoachSessionState()
            try await store.start()
            WorkoutHapticCoordinator.resetRestState()
            await refreshMetadata()
            if let snapshot = store.snapshot {
                await sideEffects.onSessionStarted(snapshot)
                activateWatchCompanionAfterSessionStart()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startTodaysPrescription() async {
        do {
            try await WorkoutStartCoordinator.startTodaysSession(
                controller: self,
                prescriptionService: prescriptionService
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startPrescription(_ prescription: SessionPrescription) async {
        guard !prescription.exercises.isEmpty else {
            errorMessage = "No prescription available for today."
            return
        }
        do {
            applyPrescriptionTargets(from: prescription)
            resetCoachSessionState()
            try await store.startFromPrescription(prescription)
            WorkoutHapticCoordinator.resetRestState()
            await refreshMetadata()
            if let snapshot = store.snapshot {
                await sideEffects.onSessionStarted(snapshot)
                activateWatchCompanionAfterSessionStart()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startWorkout(fromTemplateID templateID: String) async {
        do {
            exerciseTargets = [:]
            resetCoachSessionState()
            guard let template = try persistence.workoutTemplates.fetch(id: templateID) else {
                errorMessage = "Template not found."
                return
            }
            try await store.startFromTemplate(template)
            WorkoutHapticCoordinator.resetRestState()
            await refreshMetadata()
            if let snapshot = store.snapshot {
                await sideEffects.onSessionStarted(snapshot)
                activateWatchCompanionAfterSessionStart()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startWorkout(fromImportedPlan plan: ImportedWorkoutPlan, saveTemplate: Bool) async {
        do {
            exerciseTargets = [:]
            resetCoachSessionState()
            if saveTemplate {
                let template = WorkoutTemplateDraft(
                    name: plan.title,
                    exercises: plan.exercises.map { exercise in
                        let reps = exercise.sets.compactMap(\.reps)
                        return WorkoutTemplateExerciseDraft(
                            exerciseID: exercise.exerciseID,
                            displayOrder: exercise.displayOrder,
                            targetSetCount: max(exercise.sets.count, 1),
                            targetRepMin: reps.min(),
                            targetRepMax: reps.max(),
                            targetMass: exercise.sets.compactMap(\.mass).first,
                            defaultRestSeconds: exercise.restDurationSeconds ?? 90
                        )
                    }
                )
                try persistence.workoutTemplates.insert(template)
            }
            try await store.startFromImport(plan)
            WorkoutHapticCoordinator.resetRestState()
            await refreshMetadata()
            if let snapshot = store.snapshot {
                await sideEffects.onSessionStarted(snapshot)
                activateWatchCompanionAfterSessionStart()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func finishWorkout() async {
        do {
            let skipPhoneEnergy = watchCompanionDeliveredHeartRate
            let finishedID = try await store.finish()
            deactivateWatchCompanion(saveWatchWorkout: true)
            isShowingFinishConfirmation = false
            numpadTarget = nil
            exerciseTargets = [:]
            resetCoachSessionState()
            cancelWatchLiveConfirm()
            await refreshMetadata()
            prescriptionAutoStartStore.suppressAutoStart(for: todayHelmDay())
            if let finishedID {
                await sideEffects.onSessionFinished(
                    sessionID: finishedID,
                    writePhoneEnergyEstimate: !skipPhoneEnergy
                )
                let samples = sessionHeartRateBuffer.samples
                stopHeartRateSampling(reset: true)
                watchCompanionDeliveredHeartRate = false
                didRelaunchWatchForReachability = false
                if let session = try? persistence.workoutSessions.fetch(id: finishedID) {
                    let records = (try? PersonalRecordDetector.detect(in: session, repository: persistence.workoutSessions)) ?? []
                    lastFinishedPersonalRecords = records
                    let markers = SessionSetMarkerBuilder.markers(
                        from: session,
                        startedAt: session.startedAt
                    )
                    if let summary = try? WorkoutFinishSummaryAssembler.build(
                        session: session,
                        store: persistence
                    ) {
                        lastFinishSummary = summary.withHeartRate(
                            samples: samples,
                            setMarkers: markers
                        )
                    } else {
                        lastFinishSummary = nil
                    }
                    await ProactiveBootstrap.notificationScheduler.postPostWorkoutSummary(
                        session: session,
                        personalRecords: records
                    )
                    await ProactiveBootstrap.notificationScheduler.cancelPreWorkoutPrime(
                        for: HelmDay.day(for: .now, calendar: .current)
                    )
                    isShowingFinishSummary = lastFinishSummary != nil
                    if lastFinishSummary == nil {
                        presentPersonalRecordsIfNeeded(records)
                    }
                } else {
                    WorkoutHapticCoordinator.playSessionFinished()
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func discardWorkout() async {
        do {
            let sessionID = store.snapshot?.session.id
            try await store.discard()
            deactivateWatchCompanion(saveWatchWorkout: false)
            isShowingDiscardConfirmation = false
            numpadTarget = nil
            exerciseTargets = [:]
            resetCoachSessionState()
            cancelWatchLiveConfirm()
            stopHeartRateSampling(reset: true)
            watchCompanionDeliveredHeartRate = false
            didRelaunchWatchForReachability = false
            prescriptionAutoStartStore.suppressAutoStart(for: todayHelmDay())
            await refreshMetadata()
            await refreshPrescriptionState()
            if let sessionID {
                await sideEffects.onSessionDiscarded(sessionID: sessionID)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func retryWatchCompanionLaunch() {
        guard store.snapshot != nil else { return }
        watchCompanionNotice = nil
        didRelaunchWatchForReachability = false
        activateWatchCompanionAfterSessionStart()
    }

    func handleWatchReachabilityChange(isReachable: Bool) {
        guard isReachable, store.snapshot != nil else { return }
        guard WatchReadinessBootstrap.coordinator.canDriveWatchCompanion else { return }
        guard !watchCompanionDeliveredHeartRate, !didRelaunchWatchForReachability else { return }
        didRelaunchWatchForReachability = true
        Task { @MainActor in
            pushWatchCompanionState()
            _ = await WatchReadinessBootstrap.coordinator.launchWatchWorkoutCompanion()
            pushWatchCompanionState()
            scheduleWatchLiveConfirm()
        }
    }

    func addExercise(exerciseID: String) async {
        do {
            try await store.addExercise(exerciseID: exerciseID)
            isShowingExercisePicker = false
            await refreshMetadata()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func requestRemoveExercise(sessionExerciseID: String) {
        pendingExerciseRemoval.request(sessionExerciseID)
    }

    func cancelRemoveExercise() {
        pendingExerciseRemoval.cancel()
    }

    func confirmRemoveExercise(presentingID: String? = nil) async {
        guard let sessionExerciseID = pendingExerciseRemoval.confirm(presentingID: presentingID) else {
            return
        }
        await removeExercise(sessionExerciseID: sessionExerciseID)
    }

    func removeExercise(sessionExerciseID: String) async {
        do {
            try await store.removeExercise(sessionExerciseID: sessionExerciseID)
            await refreshMetadata()
            pushWatchCompanionState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addSet(sessionExerciseID: String) async {
        guard let exercise = store.snapshot?.session.exercises.first(where: { $0.id == sessionExerciseID }) else {
            return
        }
        do {
            try await store.adjustExerciseSetCount(
                sessionExerciseID: sessionExerciseID,
                targetSetCount: exercise.sets.count + 1
            )
            await refreshMetadata()
            pushWatchCompanionState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeSet(sessionExerciseID: String) async {
        guard let exercise = store.snapshot?.session.exercises.first(where: { $0.id == sessionExerciseID }) else {
            return
        }
        guard exercise.sets.count > 1 else { return }
        do {
            try await store.adjustExerciseSetCount(
                sessionExerciseID: sessionExerciseID,
                targetSetCount: exercise.sets.count - 1
            )
            await refreshMetadata()
            pushWatchCompanionState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func completeSet(sessionExerciseID: String, setID: String) async {
        do {
            guard let existingSet = findSet(setID: setID) else { return }
            let completedBefore = store.snapshot.map {
                TrainSessionProgress.from(snapshot: $0).completedSetCount
            } ?? 0

            if existingSet.status == .completed {
                try await store.uncompleteSet(sessionExerciseID: sessionExerciseID, setID: setID)
                HapticEngine.shared.play(.selection)
                numpadTarget = nil
                sessionPRRecordsBySetID.removeValue(forKey: setID)
                encouragementGlyphBySetID.removeValue(forKey: setID)
                rirAdvisoryBySetID.removeValue(forKey: setID)
                if prCelebrationSetID == setID {
                    prCelebrationSetID = nil
                }
                lastSetPersonalRecords = []
                await refreshMetadata()
                await syncSideEffects(force: true)
                return
            }

            if let target = numpadTarget, target.setID == setID {
                guard await applyNumpadInput() else { return }
            }

            guard let refreshedSet = findSet(setID: setID) else { return }

            if refreshedSet.mass == nil || refreshedSet.reps == nil,
               let previous = previousFor(set: refreshedSet, exerciseID: exerciseID(for: sessionExerciseID)) {
                var mass = refreshedSet.mass
                var reps = refreshedSet.reps
                if mass == nil { mass = previous.mass }
                if reps == nil { reps = previous.reps }
                try await store.logSet(
                    setID: setID,
                    update: SetLogUpdate(
                        mass: mass,
                        reps: reps,
                        rpe: refreshedSet.rpe,
                        rir: refreshedSet.rpe.map { PlanKit.rirFromRPE($0) } ?? refreshedSet.rir
                    )
                )
                updateRIRAdvisory(
                    setID: setID,
                    exerciseID: exerciseID(for: sessionExerciseID),
                    mass: mass,
                    reps: reps,
                    rpe: refreshedSet.rpe,
                    setType: refreshedSet.setType
                )
            }
            try await store.completeSet(sessionExerciseID: sessionExerciseID, setID: setID)
            numpadTarget = nil
            await refreshMetadata()

            let exerciseID = exerciseID(for: sessionExerciseID)
            let completedSet = findSet(setID: setID) ?? refreshedSet
            let personalRecords = registerPersonalRecords(
                for: completedSet,
                exerciseID: exerciseID,
                setID: setID
            )
            lastSetPersonalRecords = personalRecords

            if personalRecords.isEmpty {
                WorkoutHapticCoordinator.playSetCompletion(wasAlreadyCompleted: false)
                registerEncouragementGlyphIfNeeded(
                    for: completedSet,
                    sessionExerciseID: sessionExerciseID,
                    setID: setID
                )
            } else {
                WorkoutHapticCoordinator.playPersonalRecords(personalRecords)
                prCelebrationSetID = setID
                schedulePRCelebrationClear(for: setID)
            }

            await syncSideEffects(force: true)
            evaluateSessionMilestoneAfterSetComplete(previousCompleted: completedBefore)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func evaluateSessionMilestoneAfterSetComplete(previousCompleted: Int) {
        guard ProactiveCoachPreferences.milestonesEnabled else { return }
        guard let snapshot = store.snapshot else { return }
        let progress = TrainSessionProgress.from(snapshot: snapshot)
        guard let quartile = SessionMilestonePolicy.crossedMilestone(
            previousCompleted: previousCompleted,
            completed: progress.completedSetCount,
            total: progress.totalSetCount,
            alreadyFiredQuartiles: firedMilestoneQuartiles
        ) else {
            return
        }
        firedMilestoneQuartiles.insert(quartile)
        ProactiveCoachRouter.surface(
            SessionMilestonePolicy.message(forQuartile: quartile),
            sessionID: snapshot.session.id,
            on: self
        )
    }

    func badgeText(forSetID setID: String) -> String? {
        guard let records = sessionPRRecordsBySetID[setID], !records.isEmpty else { return nil }
        return WorkoutPersonalRecordFormatter.badgeText(for: records)
    }

    func showsPRCelebration(forSetID setID: String) -> Bool {
        prCelebrationSetID == setID
    }

    func encouragementGlyph(forSetID setID: String) -> EncouragementGlyph? {
        encouragementGlyphBySetID[setID]
    }

    func rirAdvisory(forSetID setID: String) -> String? {
        rirAdvisoryBySetID[setID]
    }

    func skipRest() async {
        do {
            try await store.skipRest()
            await refreshMetadata()
            await syncSideEffects(force: true)
            syncRestTimerMonitor()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startManualRest(durationSeconds: Int) async {
        do {
            try await store.startManualRestTimer(durationSeconds: durationSeconds)
            HapticEngine.shared.play(.selection)
            await refreshMetadata()
            await syncSideEffects(force: true)
            syncRestTimerMonitor()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func adjustRestTimer(deltaSeconds: Int) async {
        do {
            try await store.adjustRestTimer(deltaSeconds: deltaSeconds)
            HapticEngine.shared.play(.selection)
            await refreshMetadata()
            await syncSideEffects(force: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateSessionNote(_ text: String) {
        sessionNoteText = text
        sessionNoteIsDirty = true
        sessionNoteSavedConfirmation = false
        sessionNoteSaveTask?.cancel()
        sessionNoteSaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await persistSessionNote()
        }
    }

    func saveSessionNoteToMemory() async {
        let trimmed = sessionNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            await persistSessionNote()
            var profile = try persistence.memoryProfile.load()
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            let dateLine = formatter.string(from: Date())
            let line = "\(dateLine): \(trimmed)"
            if profile.standingConstraints.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                profile.standingConstraints = line
            } else {
                profile.standingConstraints += "\n" + line
            }
            try persistence.memoryProfile.save(profile)
            sessionNoteSavedConfirmation = true
            HapticEngine.shared.play(.mealConfirmed)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func enterReorderMode() {
        guard let exercises = store.snapshot?.session.exercises, !exercises.isEmpty else { return }
        reorderDraftIDs = exercises.map(\.id)
        isReorderMode = true
    }

    func cancelReorderMode() {
        isReorderMode = false
        reorderDraftIDs = []
    }

    func moveExerciseInDraft(from sourceID: String, to destinationID: String) {
        guard isReorderMode, sourceID != destinationID,
              let fromIndex = reorderDraftIDs.firstIndex(of: sourceID),
              let toIndex = reorderDraftIDs.firstIndex(of: destinationID),
              fromIndex != toIndex else {
            return
        }
        reorderDraftIDs.move(
            fromOffsets: IndexSet(integer: fromIndex),
            toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex
        )
        HapticEngine.shared.play(.selection)
    }

    func commitReorder() async {
        guard isReorderMode else { return }
        let orderedIDs = reorderDraftIDs
        isReorderMode = false
        reorderDraftIDs = []
        do {
            try await store.reorderExercises(orderedSessionExerciseIDs: orderedIDs)
            await refreshMetadata()
            pushWatchCompanionState()
            await syncSideEffects(force: true)
            HapticEngine.shared.play(.coachAdjust)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateExerciseRest(sessionExerciseID: String, seconds: Int) async {
        guard (15 ... 600).contains(seconds) else {
            errorMessage = "Rest must be between 15 and 600 seconds."
            return
        }
        do {
            try await store.updateExerciseRest(sessionExerciseID: sessionExerciseID, seconds: seconds)
            await refreshMetadata()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exercisesForDisplay() -> [WorkoutSessionExerciseDraft] {
        guard isReorderMode, !reorderDraftIDs.isEmpty,
              let exercises = store.snapshot?.session.exercises else {
            return store.snapshot?.session.exercises ?? []
        }
        let byID = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
        return reorderDraftIDs.compactMap { byID[$0] }
    }

    private func persistSessionNote() async {
        guard let sessionID = store.snapshot?.session.id else { return }
        let trimmed = sessionNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = trimmed.isEmpty ? nil : trimmed
        do {
            try await store.updateSessionNotes(notes)
            sessionNoteIsDirty = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func syncSessionNoteFromSnapshot() {
        guard !sessionNoteIsDirty, sessionNoteSaveTask == nil else { return }
        let notes = store.snapshot?.session.notes ?? ""
        guard sessionNoteText != notes else { return }
        sessionNoteText = notes
    }

    func handleScenePhase(_ phase: ScenePhase) async {
        guard store.snapshot != nil else { return }
        switch phase {
        case .background:
            coachMessageTask?.cancel()
            coachMessageTask = nil
            isCoachThinking = false
            if let snapshot = store.snapshot {
                wasRestRunningOnBackground = snapshot.restTimer?.phase == .running
                trackedRestTimerID = snapshot.restTimer?.id
                await sideEffects.onEnterBackground(
                    snapshot: snapshot,
                    restTimerSoundEnabled: trainPreferences.restTimerVolume.isEnabled
                )
            }
        case .active:
            if let snapshot = store.snapshot {
                await sideEffects.onEnterForeground(sessionID: snapshot.session.id)
            }
            await reconcileExpiredRestTimer()
            let currentRemaining = localRemainingRestSeconds()
            WorkoutHapticCoordinator.handleForegroundReturn(
                timerID: trackedRestTimerID,
                wasRunningOnBackground: wasRestRunningOnBackground,
                currentRemaining: currentRemaining
            )
            wasRestRunningOnBackground = false
            previousRestRemaining = currentRemaining
        default:
            break
        }
    }

    func handleRestRemainingSecondsChange(_ currentRemaining: Int?) {
        if let currentRemaining, currentRemaining > 0 {
            didSurfaceRestOverrunProactive = false
        }
        let timerID = snapshot?.restTimer?.id
        WorkoutHapticCoordinator.handleForegroundTransition(
            timerID: timerID,
            previousRemaining: previousRestRemaining,
            currentRemaining: currentRemaining
        )
        previousRestRemaining = currentRemaining
        trackedRestTimerID = timerID
    }

    func syncSideEffects(restRemainingOverride: Int? = nil, force: Bool = false) async {
        guard let snapshot = store.snapshot else { return }
        recordLiveHeartRateSampleIfAvailable()
        let rest = restRemainingOverride ?? localRemainingRestSeconds()
        guard shouldSyncLiveActivity(restRemaining: rest, force: force) else { return }
        lastSyncedRestRemaining = rest
        lastLiveActivitySyncDate = Date()
        let currentExercise = snapshot.session.exercises.first { exercise in
            exercise.sets.contains { $0.status != .completed }
        } ?? snapshot.session.exercises.first
        let target = currentExercise.flatMap { exerciseTargets[$0.exerciseID] }
        let bpm = WatchReadinessBootstrap.coordinator.canDriveWatchCompanion
            ? WatchReadinessBootstrap.coordinator.latestLiveHeartRateBPM
            : nil
        await sideEffects.onSessionUpdated(
            snapshot,
            restRemainingSeconds: rest,
            targetSummary: target,
            heartRateBPM: bpm
        )
    }

    func localRemainingRestSeconds(at date: Date = Date()) -> Int? {
        guard let timer = snapshot?.restTimer, timer.phase == .running else { return nil }
        return timer.remainingSeconds(at: date)
    }

    func reconcileExpiredRestTimer(at date: Date = Date()) async {
        guard let timer = snapshot?.restTimer,
              timer.phase == .running,
              timer.hasExpired(at: date) else {
            syncRestTimerMonitor()
            return
        }
        await store.recover()
        await refreshMetadata(scope: .light)
        await syncSideEffects(restRemainingOverride: 0, force: true)
        syncRestTimerMonitor()
    }

    func syncRestTimerMonitor() {
        restTimerMonitorTask?.cancel()
        restTimerMonitorTask = nil

        guard snapshot?.restTimer?.phase == .running,
              snapshot?.restTimer?.endsAt != nil else {
            return
        }

        restTimerMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let now = Date()
                let remaining = localRemainingRestSeconds(at: now) ?? 0
                handleRestRemainingSecondsChange(remaining)

                guard let timer = snapshot?.restTimer,
                      timer.phase == .running,
                      let endsAt = timer.endsAt else {
                    return
                }

                // Display remaining can floor to 0 while endsAt is still in the future.
                // Only reconcile on true expiry; otherwise sleep until endsAt (or 1s for ticks).
                if timer.hasExpired(at: now) {
                    await reconcileExpiredRestTimer(at: now)
                    return
                }

                let untilExpiry = endsAt.timeIntervalSince(now)
                let sleepSeconds = min(1.0, max(0.05, untilExpiry))
                try? await Task.sleep(for: .seconds(sleepSeconds))
            }
        }
    }

    private func shouldSyncLiveActivity(restRemaining: Int?, force: Bool) -> Bool {
        if force { return true }
        if restRemaining == nil || restRemaining == 0 {
            return lastSyncedRestRemaining != restRemaining
        }
        if let last = lastSyncedRestRemaining,
           let rest = restRemaining,
           abs(last - rest) < 15,
           let lastSync = lastLiveActivitySyncDate,
           Date().timeIntervalSince(lastSync) < 15 {
            return false
        }
        return true
    }

    func displayName(for exerciseID: String) -> String {
        exerciseSummaries[exerciseID]?.displayName ?? exerciseID
    }

    /// Next incomplete exercise after the one tied to the running rest timer (or current work).
    var upNextExerciseName: String? {
        guard let snapshot else { return nil }
        let exercises = snapshot.session.exercises
        guard !exercises.isEmpty else { return nil }

        let anchorID = snapshot.restTimer?.sessionExerciseID
            ?? exercises.first(where: { exercise in
                exercise.sets.contains { $0.status != .completed }
            })?.id

        guard let anchorID,
              let anchorIndex = exercises.firstIndex(where: { $0.id == anchorID }) else {
            return nil
        }

        let next = exercises[(anchorIndex + 1)...].first { exercise in
            exercise.sets.contains { $0.status != .completed }
        }
        guard let next else { return nil }
        return displayName(for: next.exerciseID)
    }

    var sessionProgress: TrainSessionProgress? {
        guard let snapshot else { return nil }
        return TrainSessionProgress.from(snapshot: snapshot)
    }

    func openExerciseHistory(sessionExerciseID: String) {
        historyExerciseSessionID = sessionExerciseID
    }

    func dismissExerciseHistory() {
        historyExerciseSessionID = nil
    }

    func exerciseHistoryModel(for sessionExerciseID: String) -> ExerciseHistoryModel? {
        guard let snapshot,
              let exercise = snapshot.session.exercises.first(where: { $0.id == sessionExerciseID }) else {
            return nil
        }

        return try? ExerciseHistoryBuilder.build(
            exercise: exercise,
            displayName: displayName(for: exercise.exerciseID),
            previousLookup: { [self] set in
                previousFor(set: set, exerciseID: exercise.exerciseID)
            },
            store: persistence,
            excludingSessionID: snapshot.session.id
        )
    }

    func coachingCue(for exerciseID: String) -> String? {
        guard let sessionID = snapshot?.session.id else { return nil }
        let coachingCues = (try? persistence.exercises.fetchCoachingCues(id: exerciseID)) ?? []
        let instruction = try? persistence.exercises.fetchInstructionText(id: exerciseID)
        return ExerciseCoachingCuePicker.cue(
            coachingCues: coachingCues,
            instructionText: instruction,
            exerciseID: exerciseID,
            sessionID: sessionID
        )
    }

    func displayName(forExerciseSessionID sessionExerciseID: String) -> String {
        guard let exercise = store.snapshot?.session.exercises.first(where: { $0.id == sessionExerciseID }) else {
            return "this exercise"
        }
        return displayName(for: exercise.exerciseID)
    }

    func previousFor(set: SetEntryDraft, exerciseID: String) -> PreviousPerformance? {
        previousPerformance[previousKey(exerciseID: exerciseID, setIndex: set.setIndex, setType: set.setType)]
    }

    func openNumpad(
        setID: String,
        sessionExerciseID: String,
        field: NumpadFieldKind,
        currentSet: SetEntryDraft
    ) async {
        let nextTarget = NumpadTarget(setID: setID, sessionExerciseID: sessionExerciseID, field: field)
        if numpadTarget == nextTarget {
            if hasStoredValue(for: field, set: currentSet) {
                numpadSelectAll = true
            } else {
                numpadSelectAll = false
            }
            numpadValidationError = nil
            return
        }

        if numpadTarget != nil {
            guard await applyNumpadInput() else { return }
        }

        let exerciseID = exerciseID(for: sessionExerciseID)
        let set = findSet(setID: setID) ?? currentSet
        withAnimation(HelmMotion.settleAnimation) {
            numpadTarget = nextTarget
        }
        numpadValidationError = nil
        seedNumpad(for: field, set: set, exerciseID: exerciseID)
    }

    func dismissNumpad() async {
        guard numpadTarget != nil else { return }
        if numpadTarget?.field == .rpe {
            withAnimation(HelmMotion.settleAnimation) {
                numpadTarget = nil
            }
            numpadValidationError = nil
            numpadSelectAll = false
            return
        }
        guard await applyNumpadInput() else { return }
        withAnimation(HelmMotion.settleAnimation) {
            numpadTarget = nil
        }
        numpadSelectAll = false
    }

    func completeSetFromRPEDone() async {
        guard let target = numpadTarget else { return }
        numpadWorkingText = formattedRPE(numpadDraftRPE)
        guard await applyNumpadInput() else { return }
        await completeSet(sessionExerciseID: target.sessionExerciseID, setID: target.setID)
    }

    @discardableResult
    func applyNumpadInput() async -> Bool {
        guard let target = numpadTarget,
              let set = findSet(setID: target.setID) else { return true }

        let text = target.field == .rpe ? formattedRPE(numpadDraftRPE) : numpadWorkingText

        if let error = SetLogValidation.validate(field: target.field, text: text) {
            rejectNumpadValidation(error)
            return false
        }

        let normalized = SetLogValidation.normalizedNumpadText(text)
        let update = numpadUpdate(for: target.field, text: normalized, existing: set)
        do {
            try await store.logSet(setID: target.setID, update: update)
            await refreshMetadata(scope: .light)
            numpadValidationError = nil
            updateRIRAdvisory(
                setID: target.setID,
                exerciseID: exerciseID(for: target.sessionExerciseID),
                mass: update.mass,
                reps: update.reps,
                rpe: update.rpe,
                setType: set.setType
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func advanceNumpad() async {
        guard let target = numpadTarget else { return }
        guard await applyNumpadInput() else { return }

        guard let set = findSet(setID: target.setID) else {
            numpadTarget = nil
            return
        }

        let exerciseID = exerciseID(for: target.sessionExerciseID)
        let nextField: NumpadFieldKind? = switch target.field {
        case .weight: .reps
        case .reps: .rpe
        case .rpe: nil
        }

        if let nextField {
            numpadTarget = NumpadTarget(
                setID: target.setID,
                sessionExerciseID: target.sessionExerciseID,
                field: nextField
            )
            numpadValidationError = nil
            numpadWorkingText = ""
        } else {
            numpadTarget = nil
            numpadValidationError = nil
        }
    }

    func cycleSetType(setID: String) async {
        if let target = numpadTarget, target.setID != setID {
            guard await applyNumpadInput() else { return }
        }
        guard let set = findSet(setID: setID) else { return }
        let nextType = set.setType.cycledForLogger()
        do {
            try await store.updateSetType(setID: setID, setType: nextType)
            await refreshMetadata()
            HapticEngine.shared.play(.selection)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func appendNumpadDigit(_ digit: String) {
        guard !digit.isEmpty else { return }
        if digit == ".", !SetLogValidation.allowsAppendingDecimal(to: numpadWorkingText) {
            return
        }
        numpadValidationError = nil
        if numpadSelectAll {
            numpadWorkingText = digit == "." ? "0." : digit
            numpadSelectAll = false
            return
        }
        if numpadWorkingText == "0", digit != "." {
            numpadWorkingText = digit
        } else {
            numpadWorkingText += digit
        }
    }

    func backspaceNumpad() {
        if numpadSelectAll {
            numpadWorkingText = ""
            numpadSelectAll = false
            return
        }
        guard !numpadWorkingText.isEmpty else { return }
        numpadWorkingText.removeLast()
    }

    func fillFromPrevious(setID: String, sessionExerciseID: String) async {
        guard let set = findSet(setID: setID),
              let previous = previousFor(set: set, exerciseID: exerciseID(for: sessionExerciseID)) else { return }
        do {
            try await store.logSet(
                setID: setID,
                update: SetLogUpdate(
                    mass: previous.mass ?? set.mass,
                    reps: previous.reps ?? set.reps,
                    rpe: set.rpe,
                    rir: set.rpe.map { PlanKit.rirFromRPE($0) } ?? set.rir
                )
            )
            await refreshMetadata()
            updateRIRAdvisory(
                setID: setID,
                exerciseID: exerciseID(for: sessionExerciseID),
                mass: previous.mass ?? set.mass,
                reps: previous.reps ?? set.reps,
                rpe: set.rpe,
                setType: set.setType
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearFinishedPersonalRecords() {
        lastFinishedPersonalRecords = []
    }

    func clearFinishSummary() {
        lastFinishSummary = nil
    }

    func dismissFinishSummary() {
        isShowingFinishSummary = false
        presentPersonalRecordsIfNeeded(lastFinishedPersonalRecords)
    }

    private func presentPersonalRecordsIfNeeded(_ records: [DetectedPersonalRecord]) {
        guard !records.isEmpty else { return }
        WorkoutHapticCoordinator.playPersonalRecords(records)
        isShowingPersonalRecords = true
    }

    func sendCoachMessage() async {
        let trimmed = coachPromptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isCoachThinking else { return }
        if hasActiveSession {
            if CoachActivityGate.shared.isBlocked(for: .inSession) {
                coachTurnError = CoachActivityGate.shared.blockingMessage(for: .inSession)
                return
            }
        } else if prescriptionSummary == nil {
            coachTurnError = "No prescription available."
            return
        }

        coachMessageTask?.cancel()
        coachMessageTask = Task { @MainActor in
            if hasActiveSession {
                await performSendCoachMessage(trimmed)
            } else {
                await performSendPreStartCoachMessage(trimmed)
            }
        }
        await coachMessageTask?.value
    }

    func retryLastCoachMessage() async {
        guard let lastFailedCoachMessage, !isCoachThinking else { return }
        coachPromptText = lastFailedCoachMessage
        await sendCoachMessage()
    }

    private func performSendPreStartCoachMessage(_ trimmed: String) async {
        guard !Task.isCancelled else { return }

        coachMessages.append(InSessionCoachMessage(role: .user, text: trimmed))
        coachPromptText = ""
        pendingCoachProposal = nil
        coachTurnError = nil
        lastFailedCoachMessage = trimmed
        isCoachThinking = true
        CoachActivityGate.shared.begin(.inSession)
        defer {
            isCoachThinking = false
            coachMessageTask = nil
            CoachActivityGate.shared.end(.inSession)
        }

        do {
            guard !Task.isCancelled else { return }
            let readiness = ReadinessBootstrap.readinessService.state.score
            let prescription = try await prescriptionService.todaysPrescription(readiness: readiness)
            let profile = try persistence.memoryProfile.load()
            let endDay = todayHelmDay()
            let context = try await CoachContextAssembler.assemble(from: persistence, endingAt: endDay)
            let provider = ProviderRegistry.shared.provider(for: providerPreferences.selectedProvider)

            let proposal = try await preStartCoach.proposeAdjustment(
                userMessage: trimmed,
                prescription: prescription,
                excludedExerciseIDs: excludedExerciseIDs,
                provider: provider,
                profile: profile,
                context: context,
                thread: coachThread
            )

            coachThread.messages.append(CoachMessage(role: .user, text: trimmed))
            coachThread.messages.append(CoachMessage(role: .assistant, text: proposal.reply))
            coachMessages.append(InSessionCoachMessage(role: .assistant, text: proposal.reply))
            lastCoachRequestID = proposal.requestID
            lastFailedCoachMessage = nil
            CoachDiagnosticsStore.shared.clear()

            if proposal.requiresConfirmation {
                pendingCoachProposal = proposal
                isShowingCoachPrompt = true
            } else {
                pendingCoachProposal = nil
                if let failureNotice = proposal.failureNotice {
                    coachMessages.append(InSessionCoachMessage(role: .assistant, text: failureNotice))
                    coachThread.messages.append(CoachMessage(role: .assistant, text: failureNotice))
                }
            }
        } catch InSessionCoachError.providerUnavailable(let message) {
            coachTurnError = message
            CoachDiagnosticsStore.shared.recordFailure(
                surface: "preStart",
                error: InSessionCoachError.providerUnavailable(message)
            )
            Task {
                await DiagnosticsLog.shared.record(
                    category: .coachLLM,
                    level: .error,
                    message: "Pre-start coach turn failed",
                    context: ["surface": "preStart", "error": String(describing: InSessionCoachError.providerUnavailable(message))]
                )
            }
        } catch {
            coachTurnError = CoachUserFacingError.message(for: error)
            CoachDiagnosticsStore.shared.recordFailure(
                surface: "preStart",
                error: error,
                requestID: lastCoachRequestID
            )
            Task {
                await DiagnosticsLog.shared.capture(
                    error: error,
                    category: .coachLLM,
                    message: "Pre-start coach turn failed",
                    context: ["surface": "preStart"]
                )
            }
        }
    }

    private func performSendCoachMessage(_ trimmed: String) async {
        guard !Task.isCancelled else { return }
        guard let snapshot = store.snapshot else {
            errorMessage = "No active session."
            return
        }

        coachMessages.append(InSessionCoachMessage(role: .user, text: trimmed))
        coachPromptText = ""
        pendingCoachProposal = nil
        coachTurnError = nil
        lastFailedCoachMessage = trimmed
        isCoachThinking = true
        CoachActivityGate.shared.begin(.inSession)
        defer {
            isCoachThinking = false
            coachMessageTask = nil
            CoachActivityGate.shared.end(.inSession)
        }

        do {
            guard !Task.isCancelled else { return }
            let profile = try persistence.memoryProfile.load()
            let endDay = HelmDay.day(for: .now, calendar: .current)
            let context = try await CoachContextAssembler.assemble(from: persistence, endingAt: endDay)
            let provider = ProviderRegistry.shared.provider(for: providerPreferences.selectedProvider)

            let proposal = try await inSessionCoach.proposeAdjustment(
                userMessage: trimmed,
                snapshot: snapshot,
                excludedExerciseIDs: excludedExerciseIDs,
                provider: provider,
                profile: profile,
                context: context,
                thread: coachThread
            )

            coachThread.messages.append(CoachMessage(role: .user, text: trimmed))
            coachThread.messages.append(CoachMessage(role: .assistant, text: proposal.reply))
            coachMessages.append(InSessionCoachMessage(role: .assistant, text: proposal.reply))
            lastCoachRequestID = proposal.requestID
            lastFailedCoachMessage = nil
            CoachDiagnosticsStore.shared.clear()

            if proposal.requiresConfirmation {
                pendingCoachProposal = proposal
                isShowingCoachPrompt = true
            } else {
                pendingCoachProposal = nil
                if let failureNotice = proposal.failureNotice {
                    coachMessages.append(InSessionCoachMessage(role: .assistant, text: failureNotice))
                    coachThread.messages.append(CoachMessage(role: .assistant, text: failureNotice))
                }
            }
        } catch InSessionCoachError.providerUnavailable(let message) {
            coachTurnError = message
            CoachDiagnosticsStore.shared.recordFailure(
                surface: "inSession",
                error: InSessionCoachError.providerUnavailable(message)
            )
            Task {
                await DiagnosticsLog.shared.record(
                    category: .coachLLM,
                    level: .error,
                    message: "In-session coach turn failed",
                    context: ["surface": "inSession", "error": message]
                )
            }
        } catch {
            coachTurnError = CoachUserFacingError.message(for: error)
            CoachDiagnosticsStore.shared.recordFailure(
                surface: "inSession",
                error: error,
                requestID: lastCoachRequestID
            )
            Task {
                await DiagnosticsLog.shared.capture(
                    error: error,
                    category: .coachLLM,
                    message: "In-session coach turn failed",
                    context: ["surface": "inSession"]
                )
            }
        }
    }

    func confirmCoachProposal() async {
        guard let proposal = pendingCoachProposal else { return }

        isCoachThinking = true
        defer { isCoachThinking = false }

        if let snapshot = store.snapshot {
            do {
                let applied = try inSessionCoach.applyProposal(
                    proposal,
                    snapshot: snapshot,
                    excludedExerciseIDs: excludedExerciseIDs
                )
                pendingCoachProposal = nil
                isShowingCoachPrompt = false
                try await finishApplyingAdjustment(applied)
                HapticEngine.shared.play(.phaseChange)
                showCoachApplyWave = true
            } catch InSessionCoachError.adjustmentRejected {
                WorkoutHapticCoordinator.play(.clampRejected)
                pendingCoachProposal = nil
                appendCoachFailureNotice("That adjustment is outside safe bounds.")
            } catch InSessionCoachError.noApplicableChange {
                pendingCoachProposal = nil
                appendCoachFailureNotice("That change couldn't be applied. Ask the coach to try again.")
            } catch {
                pendingCoachProposal = nil
                appendCoachFailureNotice(error.localizedDescription)
            }
            return
        }

        do {
            let readiness = ReadinessBootstrap.readinessService.state.score
            let prescription = try await prescriptionService.todaysPrescription(readiness: readiness)
            let adjusted = try preStartCoach.applyProposal(
                proposal,
                prescription: prescription,
                excludedExerciseIDs: excludedExerciseIDs,
                day: todayHelmDay()
            )
            pendingCoachProposal = nil
            await prescriptionService.refresh(readiness: readiness)
            prescriptionSummary = prescriptionService.state.summary
            applyPrescriptionTargets(from: adjusted)
            let names = try persistence.exercises.displayNames(for: adjusted.exercises.map(\.exerciseID))
            let acknowledgement = "Updated today's plan: \(adjusted.exercises.map { names[$0.exerciseID] ?? $0.exerciseID }.joined(separator: ", "))."
            coachMessages.append(InSessionCoachMessage(role: .assistant, text: acknowledgement))
            coachThread.messages.append(CoachMessage(role: .assistant, text: acknowledgement))
            HapticEngine.shared.play(.phaseChange)
            showCoachApplyWave = true
        } catch {
            pendingCoachProposal = nil
            appendCoachFailureNotice(error.localizedDescription)
        }
    }

    private func appendCoachFailureNotice(_ text: String) {
        coachMessages.append(InSessionCoachMessage(role: .assistant, text: text))
        coachThread.messages.append(CoachMessage(role: .assistant, text: text))
    }

    func dismissCoachProposal() async {
        guard let proposal = pendingCoachProposal else { return }

        do {
            try inSessionCoach.dismissProposal(recommendationID: proposal.recommendationID)
            pendingCoachProposal = nil
            let acknowledgement = "Keeping the current plan."
            coachMessages.append(InSessionCoachMessage(role: .assistant, text: acknowledgement))
            coachThread.messages.append(CoachMessage(role: .assistant, text: acknowledgement))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func submitCoachPrompt() async {
        await sendCoachMessage()
    }

    func applyFixtureAdjustment(_ payload: SessionAdjustmentPayload) async throws {
        guard let snapshot = store.snapshot else {
            throw InSessionCoachError.noActiveSession
        }
        let applied = try inSessionCoach.applyAdjustment(
            payload: payload,
            snapshot: snapshot,
            excludedExerciseIDs: excludedExerciseIDs
        )
        try await finishApplyingAdjustment(applied)
    }

    func undoLastAdjustment() async {
        guard let last = undoStack.popLast() else { return }
        do {
            try await store.restoreExerciseLayout(last.previousExercises)
            adjustmentBanner = nil
            for id in last.swappedExerciseIDs {
                excludedExerciseIDs.remove(id)
            }
            if let snapshot = store.snapshot {
                let prescription = ActiveSessionPrescriptionBridge.prescribedSession(from: snapshot)
                var targets: [String: String] = [:]
                for exercise in prescription.exercises {
                    targets[exercise.exerciseID] = exercise.targetSummaryText
                }
                exerciseTargets = targets
            }
            await refreshMetadata()
            await syncSideEffects(force: true)
            WorkoutHapticCoordinator.playCoachAdjustment()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func fetchPickerExercises(search: String, muscleGroup: String? = nil) throws -> [ExerciseSummary] {
        try persistence.exercises.listForPicker(search: search, muscleGroup: muscleGroup)
    }

    func fetchRecentExercises() throws -> [ExerciseSummary] {
        try persistence.exercises.listRecentlyUsed()
    }

    func fetchMuscleGroups() throws -> [String] {
        try persistence.exercises.listMuscleGroups(forPickerDefaults: true)
    }

    func dismissWatchCompanionNotice() {
        watchCompanionNotice = nil
    }

    private func activateWatchCompanionAfterSessionStart() {
        startHeartRateSampling()
        let coordinator = WatchReadinessBootstrap.coordinator
        coordinator.refreshPairingFlags()
        if coordinator.canDriveWatchCompanion {
            pushWatchCompanionState()
            Task { @MainActor in
                let launched = await coordinator.launchWatchWorkoutCompanion()
                pushWatchCompanionState()
                HapticEngine.shared.play(.phaseChange)
                if !launched {
                    watchCompanionNotice =
                        coordinator.lastLaunchError
                        ?? "Watch didn't wake. Open Signal on Watch once, then tap to retry."
                    return
                }
                watchCompanionNotice = nil
                scheduleWatchLiveConfirm()
            }
        } else {
            WatchReadinessBootstrap.coordinator.pushWorkoutCompanion(active: false, saveWatchWorkout: false)
            watchCompanionNotice = "No Apple Watch connected. Heart rate hidden. Phone will record training load energy."
        }
    }

    private func scheduleWatchLiveConfirm() {
        cancelWatchLiveConfirm()
        watchLiveConfirmTask = Task { @MainActor in
            let timeout = WatchWorkoutLaunchPolicy.confirmLiveTimeoutSeconds
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline, !Task.isCancelled {
                let coordinator = WatchReadinessBootstrap.coordinator
                if WatchWorkoutLaunchPolicy.isConfirmedLive(
                    hasHeartRate: coordinator.latestLiveHeartRateBPM != nil,
                    isReachable: coordinator.isReachable
                ) {
                    if coordinator.latestLiveHeartRateBPM != nil {
                        watchCompanionDeliveredHeartRate = true
                    }
                    watchCompanionNotice = nil
                    return
                }
                try? await Task.sleep(for: .seconds(1))
            }
            guard !Task.isCancelled, store.snapshot != nil else { return }
            let coordinator = WatchReadinessBootstrap.coordinator
            if WatchWorkoutLaunchPolicy.isConfirmedLive(
                hasHeartRate: coordinator.latestLiveHeartRateBPM != nil,
                isReachable: coordinator.isReachable
            ) {
                watchCompanionNotice = nil
                return
            }
            watchCompanionNotice = "Watch didn't wake. Open Signal on Watch once, then tap to retry."
        }
    }

    private func cancelWatchLiveConfirm() {
        watchLiveConfirmTask?.cancel()
        watchLiveConfirmTask = nil
    }

    private func startHeartRateSampling() {
        sessionHeartRateBuffer.reset()
        heartRateSampleTask?.cancel()
        heartRateSampleTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.store.snapshot != nil else { return }
                self.recordLiveHeartRateSampleIfAvailable()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func stopHeartRateSampling(reset: Bool) {
        heartRateSampleTask?.cancel()
        heartRateSampleTask = nil
        if reset {
            sessionHeartRateBuffer.reset()
        }
    }

    private func recordLiveHeartRateSampleIfAvailable() {
        guard let snapshot = store.snapshot else { return }
        guard WatchReadinessBootstrap.coordinator.canDriveWatchCompanion,
              let bpm = WatchReadinessBootstrap.coordinator.latestLiveHeartRateBPM
        else {
            return
        }
        watchCompanionDeliveredHeartRate = true
        let offset = Int(Date().timeIntervalSince(snapshot.session.startedAt))
        sessionHeartRateBuffer.record(bpm: bpm, offsetSeconds: offset)
    }

    private func pushWatchCompanionState() {
        guard let snapshot = store.snapshot else {
            return
        }
        let currentExercise = snapshot.session.exercises.first { exercise in
            exercise.sets.contains { $0.status != .completed }
        } ?? snapshot.session.exercises.first
        let currentSet = currentExercise?.sets.first { $0.status != .completed }
        let displayName = currentExercise.flatMap { exerciseSummaries[$0.exerciseID]?.displayName }
        let setNumber = currentExercise.flatMap { exercise in
            exercise.sets.firstIndex { $0.status != .completed }.map { $0 + 1 }
        }
        WatchReadinessBootstrap.coordinator.pushWorkoutCompanion(
            active: true,
            exerciseName: displayName,
            setNumber: setNumber,
            setCount: currentExercise?.sets.count,
            targetSummary: currentExercise.flatMap { exerciseTargets[$0.exerciseID] },
            sessionExerciseID: currentExercise?.id,
            setID: currentSet?.id
        )
    }

    private func deactivateWatchCompanion(saveWatchWorkout: Bool) {
        WatchReadinessBootstrap.coordinator.pushWorkoutCompanion(
            active: false,
            saveWatchWorkout: saveWatchWorkout
        )
    }

    func displayText(for field: NumpadFieldKind, set: SetEntryDraft, exerciseID: String) -> String {
        guard let target = numpadTarget, target.setID == set.id, target.field == field else {
            switch field {
            case .weight:
                guard let mass = set.mass else { return "" }
                return formatWeight(mass.kilograms)
            case .reps:
                return set.reps.map(String.init) ?? ""
            case .rpe:
                guard let rpe = set.rpe else { return "" }
                return formattedRPE(rpe)
            }
        }

        if field == .rpe {
            return formattedRPE(numpadDraftRPE)
        }
        return numpadWorkingText
    }

    private func seedNumpad(for field: NumpadFieldKind, set: SetEntryDraft, exerciseID: String) {
        if field == .rpe {
            numpadDraftRPE = set.rpe ?? 8.0
            numpadWorkingText = formattedRPE(numpadDraftRPE)
            numpadSelectAll = false
            return
        }

        let stored = storedDisplayText(for: field, set: set)
        if !stored.isEmpty {
            numpadWorkingText = stored
            numpadSelectAll = true
            return
        }

        if let prefilled = prefilledDisplayText(for: field, set: set, exerciseID: exerciseID),
           prefilled != "-" {
            numpadWorkingText = prefilled
            numpadSelectAll = false
            return
        }

        numpadWorkingText = ""
        numpadSelectAll = false
    }

    private func hasStoredValue(for field: NumpadFieldKind, set: SetEntryDraft) -> Bool {
        switch field {
        case .weight: set.mass != nil
        case .reps: set.reps != nil
        case .rpe: set.rpe != nil
        }
    }

    private func storedDisplayText(for field: NumpadFieldKind, set: SetEntryDraft) -> String {
        switch field {
        case .weight:
            guard let mass = set.mass else { return "" }
            return formatWeight(mass.kilograms)
        case .reps:
            return set.reps.map(String.init) ?? ""
        case .rpe:
            guard let rpe = set.rpe else { return "" }
            return formattedRPE(rpe)
        }
    }

    private func prefilledDisplayText(
        for field: NumpadFieldKind,
        set: SetEntryDraft,
        exerciseID: String
    ) -> String? {
        guard let previous = previousFor(set: set, exerciseID: exerciseID) else { return "-" }
        switch field {
        case .weight:
            guard let mass = previous.mass else { return "-" }
            return formatWeight(mass.kilograms)
        case .reps:
            return previous.reps.map(String.init) ?? "-"
        case .rpe:
            return "-"
        }
    }

    private func formattedRPE(_ rpe: Double) -> String {
        rpe.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", rpe)
            : String(format: "%.1f", rpe)
    }

    private func rejectNumpadValidation(_ message: String) {
        numpadValidationError = message
        numpadShakeToken += 1
        HapticEngine.shared.play(.clampRejected)
    }

    private func numpadUpdate(for field: NumpadFieldKind, text: String, existing: SetEntryDraft) -> SetLogUpdate {
        let trimmed = SetLogValidation.normalizedNumpadText(text)
        switch field {
        case .weight:
            let mass: Mass?
            if trimmed.isEmpty {
                mass = nil
            } else if let value = Double(trimmed) {
                mass = Mass(kilograms: value)
            } else {
                mass = existing.mass
            }
            return setLogUpdate(mass: mass, reps: existing.reps, rpe: existing.rpe)
        case .reps:
            let reps: Int?
            if trimmed.isEmpty {
                reps = nil
            } else if let value = Int(trimmed) {
                reps = value
            } else {
                reps = existing.reps
            }
            return setLogUpdate(mass: existing.mass, reps: reps, rpe: existing.rpe)
        case .rpe:
            let rpe: Double?
            if trimmed.isEmpty {
                rpe = nil
            } else if let value = Double(trimmed) {
                rpe = value
            } else {
                rpe = existing.rpe
            }
            return setLogUpdate(mass: existing.mass, reps: existing.reps, rpe: rpe)
        }
    }

    private func setLogUpdate(mass: Mass?, reps: Int?, rpe: Double?) -> SetLogUpdate {
        SetLogUpdate(
            mass: mass,
            reps: reps,
            rpe: rpe,
            rir: rpe.map { PlanKit.rirFromRPE($0) }
        )
    }

    private func updateRIRAdvisory(
        setID: String,
        exerciseID: String,
        mass: Mass?,
        reps: Int?,
        rpe: Double?,
        setType: SetType
    ) {
        guard setType != .warmup,
              let mass,
              let reps,
              let rpe else {
            rirAdvisoryBySetID.removeValue(forKey: setID)
            return
        }
        if let flag = PlanKit.rirConsistencyFlag(
            mass: mass,
            reps: reps,
            claimedRIR: PlanKit.rirFromRPE(rpe),
            historicalBestE1RM: historicalBestE1RM[exerciseID]
        ) {
            rirAdvisoryBySetID[setID] = flag.message
        } else {
            rirAdvisoryBySetID.removeValue(forKey: setID)
        }
    }

    func targetSummary(for exerciseID: String) -> String? {
        exerciseTargets[exerciseID]
    }

    private func abandonUntouchedPrescriptionIfNeeded() async {
        guard let snapshot = store.snapshot,
              ActiveSessionRecoveryPolicy.shouldAbandonUntouchedPrescription(snapshot) else {
            return
        }
        let sessionID = snapshot.session.id
        do {
            try await store.discard()
            exerciseTargets = [:]
            resetCoachSessionState()
            prescriptionAutoStartStore.suppressAutoStart(for: todayHelmDay())
            await refreshMetadata()
            await sideEffects.onSessionDiscarded(sessionID: sessionID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func todayHelmDay() -> HelmDay {
        HelmDay.day(for: .now, calendar: .current)
    }

    private func applyPrescriptionTargets(from prescription: SessionPrescription) {
        var targets: [String: String] = [:]
        for exercise in prescription.exercises {
            targets[exercise.exerciseID] = exercise.targetSummaryText
        }
        exerciseTargets = targets
    }

    private enum MetadataRefreshScope {
        case full
        case light
    }

    private func refreshMetadata(scope: MetadataRefreshScope = .full) async {
        guard let snapshot = store.snapshot else {
            exerciseSummaries = [:]
            previousPerformance = [:]
            historicalBestE1RM = [:]
            rirAdvisoryBySetID = [:]
            if exerciseTargets.isEmpty {
                exerciseTargets = [:]
            }
            pushWatchCompanionState()
            return
        }

        if snapshot.session.source == .prescription, exerciseTargets.isEmpty {
            let readiness = ReadinessBootstrap.readinessService.state.score
            if let prescription = try? await prescriptionService.todaysPrescription(readiness: readiness) {
                applyPrescriptionTargets(from: prescription)
            }
        } else if snapshot.session.source != .prescription {
            exerciseTargets = [:]
        }

        if scope == .full {
            var summaries: [String: ExerciseSummary] = [:]
            var previous: [String: PreviousPerformance] = [:]
            var bestE1RM: [String: Mass] = [:]

            for exercise in snapshot.session.exercises {
                if summaries[exercise.exerciseID] == nil,
                   let summary = try? persistence.exercises.fetchSummary(id: exercise.exerciseID) {
                    summaries[exercise.exerciseID] = summary
                }

                if bestE1RM[exercise.exerciseID] == nil,
                   let e1rm = try? persistence.workoutSessions.estimatedOneRM(
                    exerciseID: exercise.exerciseID,
                    excludingSessionID: snapshot.session.id
                   ) {
                    bestE1RM[exercise.exerciseID] = e1rm
                }

                for set in exercise.sets {
                    let key = previousKey(exerciseID: exercise.exerciseID, setIndex: set.setIndex, setType: set.setType)
                    if previous[key] == nil,
                       let perf = try? persistence.workoutSessions.previousPerformance(
                        exerciseID: exercise.exerciseID,
                        setIndex: set.setIndex,
                        setType: set.setType,
                        excludingSessionID: snapshot.session.id
                       ) {
                        previous[key] = perf
                    }
                }
            }

            exerciseSummaries = summaries
            previousPerformance = previous
            historicalBestE1RM = bestE1RM
            syncSessionNoteFromSnapshot()
        } else {
            for exercise in snapshot.session.exercises where exerciseSummaries[exercise.exerciseID] == nil {
                if let summary = try? persistence.exercises.fetchSummary(id: exercise.exerciseID) {
                    exerciseSummaries[exercise.exerciseID] = summary
                }
            }
            for exercise in snapshot.session.exercises where historicalBestE1RM[exercise.exerciseID] == nil {
                if let e1rm = try? persistence.workoutSessions.estimatedOneRM(
                    exerciseID: exercise.exerciseID,
                    excludingSessionID: snapshot.session.id
                ) {
                    historicalBestE1RM[exercise.exerciseID] = e1rm
                }
            }
        }

        pushWatchCompanionState()
        syncRestTimerMonitor()
    }

    private func findSet(setID: String) -> SetEntryDraft? {
        guard let snapshot = store.snapshot else { return nil }
        for exercise in snapshot.session.exercises {
            if let set = exercise.sets.first(where: { $0.id == setID }) {
                return set
            }
        }
        return nil
    }

    private func exerciseID(for sessionExerciseID: String) -> String {
        guard let snapshot = store.snapshot else { return "" }
        return snapshot.session.exercises.first(where: { $0.id == sessionExerciseID })?.exerciseID ?? ""
    }

    private func previousKey(exerciseID: String, setIndex: Int, setType: SetType) -> String {
        "\(exerciseID)|\(setIndex)|\(setType.rawValue)"
    }

    private func initialNumpadText(
        for field: NumpadFieldKind,
        set: SetEntryDraft,
        exerciseID: String
    ) -> String {
        switch field {
        case .weight:
            if let mass = set.mass {
                return formatWeight(mass.kilograms)
            }
            if let previous = previousFor(set: set, exerciseID: exerciseID), let mass = previous.mass {
                return formatWeight(mass.kilograms)
            }
            return ""
        case .reps:
            if let reps = set.reps { return String(reps) }
            if let previous = previousFor(set: set, exerciseID: exerciseID), let reps = previous.reps {
                return String(reps)
            }
            return ""
        case .rpe:
            if let rpe = set.rpe { return formatRPE(rpe) }
            return ""
        }
    }

    private func formatWeight(_ kilograms: Double) -> String {
        kilograms.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", kilograms)
            : String(format: "%.1f", kilograms)
    }

    private func formatRPE(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
    }

    private func resetCoachSessionState() {
        excludedExerciseIDs = []
        undoStack = []
        adjustmentBanner = nil
        proactiveCoachBanner = nil
        coachPeekSnippet = nil
        didSurfaceRestOverrunProactive = false
        firedMilestoneQuartiles = []
        coachPromptText = ""
        coachMessages = []
        pendingCoachProposal = nil
        coachTurnError = nil
        lastFailedCoachMessage = nil
        coachThread = .empty
        isShowingCoachPrompt = false
        isShowingPawelTimer = false
        isCoachThinking = false
        showCoachApplyWave = false
        lastCoachRequestID = nil
        resetSessionFeedbackState()
        sessionNoteText = ""
        sessionNoteSavedConfirmation = false
        sessionNoteSaveTask?.cancel()
        sessionNoteSaveTask = nil
        cancelReorderMode()
    }

    private func resetSessionFeedbackState() {
        lastSetPersonalRecords = []
        sessionPRRecordsBySetID = [:]
        encouragementGlyphBySetID = [:]
        rirAdvisoryBySetID = [:]
        historicalBestE1RM = [:]
        prCelebrationSetID = nil
        sessionPersonalRecordKeys = []
        lastEncouragementGlyph = nil
    }

    private func registerPersonalRecords(
        for set: SetEntryDraft,
        exerciseID: String,
        setID: String
    ) -> [DetectedPersonalRecord] {
        guard let sessionID = store.snapshot?.session.id else { return [] }

        let detected = (try? PersonalRecordDetector.detectIncremental(
            set: set,
            exerciseID: exerciseID,
            excludingSessionID: sessionID,
            repository: persistence.workoutSessions
        )) ?? []

        let newRecords = detected.filter { record in
            let key = PersonalRecordHapticPolicy.stableKey(
                exerciseID: record.exerciseID,
                metricType: record.metricType.rawValue
            )
            guard !sessionPersonalRecordKeys.contains(key) else { return false }
            sessionPersonalRecordKeys.insert(key)
            return true
        }

        if !newRecords.isEmpty {
            sessionPRRecordsBySetID[setID] = newRecords
        }

        return newRecords
    }

    private func registerEncouragementGlyphIfNeeded(
        for completedSet: SetEntryDraft,
        sessionExerciseID: String,
        setID: String
    ) {
        guard trainPreferences.workoutFeedbackEnabled else { return }
        guard let exercise = store.snapshot?.session.exercises.first(where: { $0.id == sessionExerciseID }) else {
            return
        }

        guard let glyph = WorkoutSetMilestonePolicy.encouragementGlyph(
            for: completedSet,
            in: exercise.sets,
            excludingLast: lastEncouragementGlyph
        ) else {
            return
        }

        lastEncouragementGlyph = glyph
        encouragementGlyphBySetID[setID] = glyph
    }

    private func schedulePRCelebrationClear(for setID: String) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.1))
            guard prCelebrationSetID == setID else { return }
            prCelebrationSetID = nil
        }
    }

    private func finishApplyingAdjustment(_ applied: AppliedSessionAdjustment) async throws {
        undoStack.append(applied)
        excludedExerciseIDs.formUnion(applied.swappedExerciseIDs)
        adjustmentBanner = applied.banner
        await store.recover()
        if let snapshot = store.snapshot {
            let prescription = ActiveSessionPrescriptionBridge.prescribedSession(from: snapshot)
            var targets: [String: String] = [:]
            for exercise in prescription.exercises {
                targets[exercise.exerciseID] = exercise.targetSummaryText
            }
            exerciseTargets = targets
        }
        await refreshMetadata()
        await syncSideEffects(force: true)
        WorkoutHapticCoordinator.playCoachAdjustment()
    }
}

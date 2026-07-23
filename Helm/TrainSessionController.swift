import Core
import CoachLLM
import DesignSystem
import Foundation
import HealthKitIngest
import Observation
import Persistence
import ReadinessKit
import SwiftUI

enum NumpadFieldKind: Hashable, Sendable {
    case weight
    case reps
    case rpe
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
    private let providerPreferences: ProviderPreferencesStore

    private(set) var exerciseSummaries: [String: ExerciseSummary] = [:]
    private(set) var previousPerformance: [String: PreviousPerformance] = [:]
    private(set) var exerciseTargets: [String: String] = [:]
    private(set) var prescriptionSummary: PrescribedSessionSummary?
    private(set) var lastFinishedPersonalRecords: [DetectedPersonalRecord] = []

    var numpadTarget: NumpadTarget?
    var numpadWorkingText = ""

    var isShowingExercisePicker = false
    var isShowingFinishConfirmation = false
    var isShowingDiscardConfirmation = false
    var isShowingPersonalRecords = false
    var errorMessage: String?

    var coachPromptText = ""
    var isShowingCoachPrompt = false
    private(set) var isCoachAdjusting = false
    private(set) var adjustmentBanner: SessionAdjustmentBannerModel?

    private var excludedExerciseIDs: Set<String> = []
    private var undoStack: [AppliedSessionAdjustment] = []

    private var previousRestRemaining: Int?
    private var wasRestRunningOnBackground = false
    private var trackedRestTimerID: String?
    private var suppressPrescriptionAutoStart = false

    init(
        store: ActiveSessionStore,
        persistence: PersistenceStore,
        sideEffects: WorkoutSessionSideEffects,
        prescriptionService: PrescriptionService,
        inSessionCoach: InSessionCoachService? = nil,
        providerPreferences: ProviderPreferencesStore = ProviderPreferencesStore()
    ) {
        self.store = store
        self.persistence = persistence
        self.sideEffects = sideEffects
        self.prescriptionService = prescriptionService
        self.inSessionCoach = inSessionCoach ?? InSessionCoachService(persistence: persistence)
        self.providerPreferences = providerPreferences
    }

    var snapshot: ActiveSessionSnapshot? {
        store.snapshot
    }

    var hasActiveSession: Bool {
        store.hasActiveSession
    }

    /// Reloads the persisted active session from the database (kill-recover, tab return).
    func recoverPersistedSession() async {
        await store.recover()
        await refreshMetadata()
    }

    /// App-launch recovery: restore an in-progress session or auto-start today's prescription once.
    func recoverOnLaunch() async {
        suppressPrescriptionAutoStart = false
        await recoverPersistedSession()
        if let snapshot = store.snapshot {
            await sideEffects.onSessionStarted(snapshot)
        } else {
            await refreshPrescriptionState()
            await tryAutoStartTodaysPrescription()
        }
    }

    func refreshPrescriptionState() async {
        let readiness = ReadinessBootstrap.readinessService.state.score
        await prescriptionService.refresh(readiness: readiness)
        prescriptionSummary = prescriptionService.state.summary
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
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startTodaysPrescription() async {
        do {
            let readiness = ReadinessBootstrap.readinessService.state.score
            let prescription = try await prescriptionService.todaysPrescription(readiness: readiness)
            guard !prescription.exercises.isEmpty else {
                errorMessage = "No prescription available for today."
                return
            }
            applyPrescriptionTargets(from: prescription)
            resetCoachSessionState()
            try await store.startFromPrescription(prescription)
            WorkoutHapticCoordinator.resetRestState()
            await refreshMetadata()
            if let snapshot = store.snapshot {
                await sideEffects.onSessionStarted(snapshot)
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
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func finishWorkout() async {
        do {
            let finishedID = try await store.finish()
            isShowingFinishConfirmation = false
            numpadTarget = nil
            exerciseTargets = [:]
            resetCoachSessionState()
            await refreshMetadata()
            if let finishedID {
                await sideEffects.onSessionFinished(sessionID: finishedID)
                if let session = try? persistence.workoutSessions.fetch(id: finishedID) {
                    let records = (try? PersonalRecordDetector.detect(in: session, repository: persistence.workoutSessions)) ?? []
                    lastFinishedPersonalRecords = records
                    await ProactiveBootstrap.notificationScheduler.postPostWorkoutSummary(
                        session: session,
                        personalRecords: records
                    )
                    await ProactiveBootstrap.notificationScheduler.cancelPreWorkoutPrime(
                        for: HelmDay.day(for: .now, calendar: .current)
                    )
                    if records.isEmpty {
                        WorkoutHapticCoordinator.playSessionFinished()
                    } else {
                        WorkoutHapticCoordinator.playPersonalRecords(records)
                    }
                    isShowingPersonalRecords = !records.isEmpty
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
            isShowingDiscardConfirmation = false
            numpadTarget = nil
            exerciseTargets = [:]
            resetCoachSessionState()
            suppressPrescriptionAutoStart = true
            await refreshMetadata()
            await refreshPrescriptionState()
            if let sessionID {
                await sideEffects.onSessionDiscarded(sessionID: sessionID)
            }
        } catch {
            errorMessage = error.localizedDescription
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

    func removeExercise(sessionExerciseID: String) async {
        do {
            try await store.removeExercise(sessionExerciseID: sessionExerciseID)
            await refreshMetadata()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func completeSet(sessionExerciseID: String, setID: String) async {
        do {
            guard let existingSet = findSet(setID: setID) else { return }
            guard existingSet.status != .completed else { return }

            if existingSet.mass == nil || existingSet.reps == nil,
               let previous = previousFor(set: existingSet, exerciseID: exerciseID(for: sessionExerciseID)) {
                var mass = existingSet.mass
                var reps = existingSet.reps
                if mass == nil { mass = previous.mass }
                if reps == nil { reps = previous.reps }
                try await store.logSet(
                    setID: setID,
                    update: SetLogUpdate(mass: mass, reps: reps, rpe: existingSet.rpe)
                )
            }
            try await store.completeSet(sessionExerciseID: sessionExerciseID, setID: setID)
            WorkoutHapticCoordinator.playSetCompletion(wasAlreadyCompleted: false)
            numpadTarget = nil
            await refreshMetadata()
            await syncSideEffects()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func skipRest() async {
        do {
            try await store.skipRest()
            await refreshMetadata()
            await syncSideEffects()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func handleScenePhase(_ phase: ScenePhase) async {
        guard let snapshot = store.snapshot else { return }
        switch phase {
        case .background:
            wasRestRunningOnBackground = snapshot.restTimer?.phase == .running
            trackedRestTimerID = snapshot.restTimer?.id
            await sideEffects.onEnterBackground(snapshot: snapshot)
        case .active:
            await sideEffects.onEnterForeground(sessionID: snapshot.session.id)
            let currentRemaining = await remainingRestSeconds()
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
        let timerID = snapshot?.restTimer?.id
        WorkoutHapticCoordinator.handleForegroundTransition(
            timerID: timerID,
            previousRemaining: previousRestRemaining,
            currentRemaining: currentRemaining
        )
        previousRestRemaining = currentRemaining
        trackedRestTimerID = timerID
    }

    func syncSideEffects() async {
        guard let snapshot = store.snapshot else { return }
        let rest = try? await store.remainingRestSeconds()
        await sideEffects.onSessionUpdated(snapshot, restRemainingSeconds: rest)
    }

    func remainingRestSeconds(at date: Date = Date()) async -> Int? {
        try? await store.remainingRestSeconds(at: date)
    }

    func displayName(for exerciseID: String) -> String {
        exerciseSummaries[exerciseID]?.displayName ?? exerciseID
    }

    func previousFor(set: SetEntryDraft, exerciseID: String) -> PreviousPerformance? {
        previousPerformance[previousKey(exerciseID: exerciseID, setIndex: set.setIndex, setType: set.setType)]
    }

    func openNumpad(
        setID: String,
        sessionExerciseID: String,
        field: NumpadFieldKind,
        currentSet: SetEntryDraft
    ) {
        let exerciseID = exerciseID(for: sessionExerciseID)
        numpadTarget = NumpadTarget(setID: setID, sessionExerciseID: sessionExerciseID, field: field)
        numpadWorkingText = initialNumpadText(for: field, set: currentSet, exerciseID: exerciseID)
    }

    func applyNumpadInput() async {
        guard let target = numpadTarget,
              let set = findSet(setID: target.setID) else { return }

        let update = numpadUpdate(for: target.field, text: numpadWorkingText, existing: set)
        do {
            try await store.logSet(setID: target.setID, update: update)
            await refreshMetadata()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func appendNumpadDigit(_ digit: String) {
        guard !digit.isEmpty else { return }
        if numpadWorkingText == "0", digit != "." {
            numpadWorkingText = digit
        } else {
            numpadWorkingText += digit
        }
    }

    func backspaceNumpad() {
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
                    rpe: set.rpe
                )
            )
            await refreshMetadata()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearFinishedPersonalRecords() {
        lastFinishedPersonalRecords = []
    }

    func submitCoachPrompt() async {
        let trimmed = coachPromptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isCoachAdjusting else { return }
        guard let snapshot = store.snapshot else {
            errorMessage = "No active session."
            return
        }

        isCoachAdjusting = true
        isShowingCoachPrompt = false
        defer { isCoachAdjusting = false }

        do {
            let profile = try persistence.memoryProfile.load()
            let endDay = HelmDay.day(for: .now, calendar: .current)
            let contextDays = try CoachContextAssembler.assemble(from: persistence, endingAt: endDay)
            let provider = ProviderRegistry.shared.provider(for: providerPreferences.selectedProvider)

            let applied = try await inSessionCoach.askCoachInSession(
                userMessage: trimmed,
                snapshot: snapshot,
                excludedExerciseIDs: excludedExerciseIDs,
                provider: provider,
                profile: profile,
                contextDays: contextDays.recent
            )

            try await finishApplyingAdjustment(applied)
            coachPromptText = ""
        } catch InSessionCoachError.adjustmentRejected {
            WorkoutHapticCoordinator.play(.clampRejected)
            errorMessage = "That adjustment is outside safe bounds."
        } catch InSessionCoachError.providerUnavailable(let message) {
            errorMessage = message
        } catch {
            errorMessage = CoachUserFacingError.message(for: error)
        }
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
            await syncSideEffects()
            WorkoutHapticCoordinator.playCoachAdjustment()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func fetchPickerExercises(search: String) throws -> [ExerciseSummary] {
        try persistence.exercises.listForPicker(search: search)
    }

    private func numpadUpdate(for field: NumpadFieldKind, text: String, existing: SetEntryDraft) -> SetLogUpdate {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
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
            return SetLogUpdate(mass: mass, reps: existing.reps, rpe: existing.rpe)
        case .reps:
            let reps: Int?
            if trimmed.isEmpty {
                reps = nil
            } else if let value = Int(trimmed) {
                reps = value
            } else {
                reps = existing.reps
            }
            return SetLogUpdate(mass: existing.mass, reps: reps, rpe: existing.rpe)
        case .rpe:
            let rpe: Double?
            if trimmed.isEmpty {
                rpe = nil
            } else if let value = Double(trimmed) {
                rpe = value
            } else {
                rpe = existing.rpe
            }
            return SetLogUpdate(mass: existing.mass, reps: existing.reps, rpe: rpe)
        }
    }

    func targetSummary(for exerciseID: String) -> String? {
        exerciseTargets[exerciseID]
    }

    private func tryAutoStartTodaysPrescription() async {
        guard !suppressPrescriptionAutoStart else { return }
        guard !store.hasActiveSession else { return }
        guard let summary = prescriptionSummary, !summary.exercises.isEmpty else { return }
        await startTodaysPrescription()
    }

    private func applyPrescriptionTargets(from prescription: SessionPrescription) {
        var targets: [String: String] = [:]
        for exercise in prescription.exercises {
            targets[exercise.exerciseID] = exercise.targetSummaryText
        }
        exerciseTargets = targets
    }

    private func refreshMetadata() async {
        guard let snapshot = store.snapshot else {
            exerciseSummaries = [:]
            previousPerformance = [:]
            if exerciseTargets.isEmpty {
                exerciseTargets = [:]
            }
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

        var summaries: [String: ExerciseSummary] = [:]
        var previous: [String: PreviousPerformance] = [:]

        for exercise in snapshot.session.exercises {
            if summaries[exercise.exerciseID] == nil,
               let summary = try? persistence.exercises.fetchSummary(id: exercise.exerciseID) {
                summaries[exercise.exerciseID] = summary
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
        coachPromptText = ""
        isShowingCoachPrompt = false
        isCoachAdjusting = false
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
        await syncSideEffects()
        WorkoutHapticCoordinator.playCoachAdjustment()
    }
}

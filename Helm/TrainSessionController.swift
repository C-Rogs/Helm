import Core
import Foundation
import Observation
import Persistence
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

    private(set) var exerciseSummaries: [String: ExerciseSummary] = [:]
    private(set) var previousPerformance: [String: PreviousPerformance] = [:]
    private(set) var lastFinishedPersonalRecords: [DetectedPersonalRecord] = []

    var numpadTarget: NumpadTarget?
    var numpadWorkingText = ""

    var isShowingExercisePicker = false
    var isShowingFinishConfirmation = false
    var isShowingDiscardConfirmation = false
    var isShowingPersonalRecords = false
    var errorMessage: String?

    init(
        store: ActiveSessionStore,
        persistence: PersistenceStore,
        sideEffects: WorkoutSessionSideEffects
    ) {
        self.store = store
        self.persistence = persistence
        self.sideEffects = sideEffects
    }

    var snapshot: ActiveSessionSnapshot? {
        store.snapshot
    }

    var hasActiveSession: Bool {
        store.hasActiveSession
    }

    func recover() async {
        await store.recover()
        await refreshMetadata()
        if let snapshot = store.snapshot {
            await sideEffects.onSessionStarted(snapshot)
        }
    }

    func startWorkout() async {
        do {
            try await store.start()
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
            guard let template = try persistence.workoutTemplates.fetch(id: templateID) else {
                errorMessage = "Template not found."
                return
            }
            try await store.startFromTemplate(template)
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
            await refreshMetadata()
            if let finishedID {
                await sideEffects.onSessionFinished(sessionID: finishedID)
                if let session = try? persistence.workoutSessions.fetch(id: finishedID) {
                    let records = (try? PersonalRecordDetector.detect(in: session, repository: persistence.workoutSessions)) ?? []
                    lastFinishedPersonalRecords = records
                    isShowingPersonalRecords = !records.isEmpty
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
            await refreshMetadata()
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
            if let set = findSet(setID: setID),
               set.mass == nil || set.reps == nil,
               let previous = previousFor(set: set, exerciseID: exerciseID(for: sessionExerciseID)) {
                var mass = set.mass
                var reps = set.reps
                if mass == nil { mass = previous.mass }
                if reps == nil { reps = previous.reps }
                try await store.logSet(
                    setID: setID,
                    update: SetLogUpdate(mass: mass, reps: reps, rpe: set.rpe)
                )
            }
            try await store.completeSet(sessionExerciseID: sessionExerciseID, setID: setID)
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
            await sideEffects.onEnterBackground(snapshot: snapshot)
        case .active:
            await sideEffects.onEnterForeground(sessionID: snapshot.session.id)
        default:
            break
        }
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

    private func refreshMetadata() async {
        guard let snapshot = store.snapshot else {
            exerciseSummaries = [:]
            previousPerformance = [:]
            return
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
}

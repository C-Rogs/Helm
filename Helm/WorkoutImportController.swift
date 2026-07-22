import Core
import DesignSystem
import Foundation
import Observation
import Persistence

@MainActor
@Observable
final class WorkoutImportController {
    private let persistence: PersistenceStore
    private let importService: WorkoutImportService
    private let resolver: WorkoutImportResolver

    private(set) var parsedWorkout: ParsedWorkout?
    private(set) var resolutions: [WorkoutImportExerciseResolution] = []
    private(set) var manualMappings: [String: String] = [:]

    var pasteText = ""
    var workoutTitle = ""
    var workoutDate = Date()
    var errorMessage: String?
    var isShowingPreview = false
    var lastImportedPersonalRecords: [DetectedPersonalRecord] = []

    init(persistence: PersistenceStore) {
        self.persistence = persistence
        importService = WorkoutImportService(
            sessions: persistence.workoutSessions,
            exercises: persistence.exercises,
            personalRecords: persistence.personalRecords
        )
        resolver = WorkoutImportResolver(exercises: persistence.exercises)
    }

    func parseForPreview() {
        errorMessage = nil
        let trimmed = pasteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = WorkoutTextParseError.emptyDocument.localizedDescription
            return
        }

        let parsed = WorkoutTextParser.parse(trimmed)
        guard !parsed.exercises.isEmpty else {
            errorMessage = "No exercises were found in the pasted text."
            return
        }

        parsedWorkout = parsed
        workoutTitle = parsed.title
        do {
            resolutions = try resolver.resolve(parsed: parsed, manualMappings: manualMappings)
            isShowingPreview = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshResolutions() {
        guard let parsedWorkout else { return }
        do {
            resolutions = try resolver.resolve(parsed: parsedWorkout, manualMappings: manualMappings)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func mapExercise(importedTitle: String, to exerciseID: String) {
        manualMappings[importedTitle] = exerciseID
        refreshResolutions()
    }

    func displayName(for exerciseID: String) -> String {
        (try? persistence.exercises.fetchSummary(id: exerciseID))?.displayName ?? exerciseID
    }

    var canImport: Bool {
        resolutions.allSatisfy(\.isResolved) && !workoutTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func importToHistory(onComplete: () -> Void) {
        guard let parsedWorkout else { return }
        errorMessage = nil

        var mappings: [String: String] = [:]
        for resolution in resolutions {
            guard let exerciseID = resolution.exerciseID else {
                errorMessage = "Map all exercises before importing."
                return
            }
            mappings[resolution.importedTitle] = exerciseID
        }

        let title = workoutTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            errorMessage = "Workout title is required."
            return
        }

        let parsedWithTitle = ParsedWorkout(
            title: title,
            exercises: parsedWorkout.exercises,
            skippedLines: parsedWorkout.skippedLines
        )

        do {
            let result = try importService.importToHistory(
                parsed: parsedWithTitle,
                mappings: mappings,
                startedAt: workoutDate,
                endedAt: workoutDate
            )
            lastImportedPersonalRecords = result.personalRecords
            WorkoutHapticCoordinator.playPersonalRecords(result.personalRecords)
            reset()
            onComplete()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reset() {
        pasteText = ""
        workoutTitle = ""
        workoutDate = Date()
        parsedWorkout = nil
        resolutions = []
        manualMappings = [:]
        isShowingPreview = false
        errorMessage = nil
    }

    func fetchPickerExercises(search: String) throws -> [ExerciseSummary] {
        try persistence.exercises.listForPicker(search: search)
    }
}

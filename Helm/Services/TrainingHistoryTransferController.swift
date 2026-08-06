import Core
import Foundation
import Observation
import Persistence
import UIKit

@MainActor
@Observable
final class TrainingHistoryTransferController {
    private let persistence: PersistenceStore
    private let hevyImportService: WorkoutImportService
    private let hevyResolver: WorkoutImportResolver
    private let trainingHistoryService: TrainingHistoryExportService

    private(set) var hevyParseResult: HevyCSVParseResult?
    private(set) var hevyResolutions: [WorkoutImportExerciseResolution] = []
    private(set) var hevyManualMappings: [String: String] = [:]
    private(set) var lastHevyImportResult: HevyBulkImportResult?
    private(set) var lastTrainingImportResult: TrainingHistoryImportResult?
    private(set) var pendingTrainingImport: TrainingHistoryExport?

    var isShowingHevyPreview = false
    var isShowingTrainingImportPreview = false
    var errorMessage: String?
    var statusMessage: String?

    init(persistence: PersistenceStore) {
        self.persistence = persistence
        hevyImportService = WorkoutImportService(
            sessions: persistence.workoutSessions,
            exercises: persistence.exercises,
            personalRecords: persistence.personalRecords
        )
        hevyResolver = WorkoutImportResolver(exercises: persistence.exercises)
        trainingHistoryService = TrainingHistoryExportService(
            sessions: persistence.workoutSessions,
            exercises: persistence.exercises
        )
    }

    var canConfirmHevyImport: Bool {
        guard let hevyParseResult, !hevyParseResult.sessions.isEmpty else { return false }
        return hevyResolutions.allSatisfy(\.isResolved)
    }

    func loadHevyCSV(from url: URL) {
        do {
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing { url.stopAccessingSecurityScopedResource() }
            }
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                errorMessage = "Could not read that file as text. Export the Hevy CSV again and retry."
                return
            }
            loadHevyCSV(text: text)
        } catch {
            errorMessage = error.localizedDescription
            hevyParseResult = nil
            hevyResolutions = []
            isShowingHevyPreview = false
        }
    }

    func loadHevyCSVFromClipboard() {
        guard let clipboard = UIPasteboard.general.string, !clipboard.isEmpty else {
            errorMessage = "Clipboard is empty. Copy the Hevy export text first."
            return
        }
        loadHevyCSV(text: clipboard)
    }

    func loadHevyCSV(text: String) {
        errorMessage = nil
        statusMessage = nil
        lastHevyImportResult = nil

        do {
            let parsed = try HevyCSVParser.parse(csvText: text)
            hevyParseResult = parsed
            hevyManualMappings = [:]
            hevyResolutions = try hevyResolver.resolve(titles: parsed.uniqueExerciseTitles)
            isShowingHevyPreview = true
        } catch {
            errorMessage = error.localizedDescription
            hevyParseResult = nil
            hevyResolutions = []
            isShowingHevyPreview = false
        }
    }

    func mapHevyExercise(importedTitle: String, to exerciseID: String) {
        hevyManualMappings[importedTitle] = exerciseID
        guard let hevyParseResult else { return }
        do {
            hevyResolutions = try hevyResolver.resolve(
                titles: hevyParseResult.uniqueExerciseTitles,
                manualMappings: hevyManualMappings
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func confirmHevyImport() {
        errorMessage = nil
        statusMessage = nil
        guard let hevyParseResult else { return }
        guard canConfirmHevyImport else {
            errorMessage = "Map every exercise before importing."
            return
        }

        var mappings: [String: String] = hevyManualMappings
        for resolution in hevyResolutions {
            if let exerciseID = resolution.exerciseID {
                mappings[resolution.importedTitle] = exerciseID
            }
        }

        do {
            let result = try hevyImportService.importHevySessions(
                hevyParseResult.sessions,
                mappings: mappings
            )
            lastHevyImportResult = result
            statusMessage =
                "Imported \(result.importedSessionCount) sessions (\(result.importedSetCount) sets). Skipped \(result.skippedDuplicateCount) duplicates."
            isShowingHevyPreview = false
            PlanBootstrap.refreshPrescription()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportTrainingHistory() throws -> URL {
        try trainingHistoryService.writeExportFile()
    }

    func loadTrainingHistory(from url: URL) {
        errorMessage = nil
        statusMessage = nil
        lastTrainingImportResult = nil
        pendingTrainingImport = nil
        isShowingTrainingImportPreview = false

        do {
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing { url.stopAccessingSecurityScopedResource() }
            }
            let data = try Data(contentsOf: url)
            let payload = try trainingHistoryService.decode(data)
            pendingTrainingImport = payload
            isShowingTrainingImportPreview = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func confirmTrainingHistoryImport() {
        errorMessage = nil
        statusMessage = nil
        guard let pendingTrainingImport else { return }

        do {
            let result = try trainingHistoryService.importHistory(pendingTrainingImport)
            lastTrainingImportResult = result
            statusMessage =
                "Restored \(result.importedSessionCount) sessions (\(result.importedSetCount) sets). Skipped \(result.skippedDuplicateCount) duplicates."
            self.pendingTrainingImport = nil
            isShowingTrainingImportPreview = false
            PlanBootstrap.refreshPrescription()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancelTrainingHistoryImport() {
        pendingTrainingImport = nil
        isShowingTrainingImportPreview = false
    }

    /// Immediate import path for tests and scripted callers.
    func importTrainingHistory(from url: URL) {
        loadTrainingHistory(from: url)
        if isShowingTrainingImportPreview {
            confirmTrainingHistoryImport()
        }
    }

    func displayName(for exerciseID: String) -> String {
        (try? persistence.exercises.fetchSummary(id: exerciseID))?.displayName ?? exerciseID
    }

    func fetchRecentExercises() throws -> [ExerciseSummary] {
        try persistence.exercises.listRecentlyUsed()
    }

    func fetchPickerExercises(search: String, muscleGroup: String? = nil) throws -> [ExerciseSummary] {
        try persistence.exercises.listForPicker(search: search, muscleGroup: muscleGroup)
    }

    func fetchMuscleGroups() throws -> [String] {
        try persistence.exercises.listMuscleGroups(forPickerDefaults: true)
    }
}

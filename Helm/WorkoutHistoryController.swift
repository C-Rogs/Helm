import Core
import Foundation
import Observation
import Persistence

@MainActor
@Observable
final class WorkoutHistoryController {
    private let persistence: PersistenceStore

    private(set) var sessions: [WorkoutSessionSummary] = []
    private(set) var templates: [WorkoutTemplateSummary] = []
    private(set) var recentPersonalRecords: [DetectedPersonalRecord] = []
    private(set) var exerciseNames: [String: String] = [:]

    var errorMessage: String?

    private let pageSize = 25
    private var loadedCount = 0
    private(set) var canLoadMore = true

    init(persistence: PersistenceStore) {
        self.persistence = persistence
    }

    func refresh() {
        do {
            loadedCount = pageSize
            sessions = try persistence.workoutSessions.listSummaries(limit: pageSize, offset: 0)
            templates = try persistence.workoutTemplates.fetchSummaries()
            canLoadMore = sessions.count == pageSize
            refreshExerciseNames()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadMoreIfNeeded(currentSessionID: String?) {
        guard canLoadMore, let currentSessionID else { return }
        guard sessions.last?.id == currentSessionID else { return }

        do {
            let next = try persistence.workoutSessions.listSummaries(limit: pageSize, offset: loadedCount)
            loadedCount += next.count
            sessions.append(contentsOf: next)
            canLoadMore = next.count == pageSize
            refreshExerciseNames()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func fetchSession(id: String) -> WorkoutSessionDraft? {
        try? persistence.workoutSessions.fetch(id: id)
    }

    func saveSession(_ draft: WorkoutSessionDraft) {
        do {
            try persistence.workoutSessions.updateCompletedSession(draft)
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createTemplate(from session: WorkoutSessionDraft, name: String) {
        do {
            _ = try persistence.workoutTemplates.createFromSession(session: session, name: name)
            templates = try persistence.workoutTemplates.fetchSummaries()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func fetchTemplate(id: String) -> WorkoutTemplateDraft? {
        try? persistence.workoutTemplates.fetch(id: id)
    }

    func displayName(for exerciseID: String) -> String {
        exerciseNames[exerciseID] ?? exerciseID
    }

    func setRecentPersonalRecords(_ records: [DetectedPersonalRecord]) {
        recentPersonalRecords = records
        refreshExerciseNames(for: records.map(\.exerciseID))
    }

    func clearRecentPersonalRecords() {
        recentPersonalRecords = []
    }

    private func refreshExerciseNames(for exerciseIDs: [String]? = nil) {
        let ids: Set<String>
        if let exerciseIDs {
            ids = Set(exerciseIDs)
        } else {
            var collected = Set<String>()
            for session in sessions {
                if let detail = fetchSession(id: session.id) {
                    collected.formUnion(detail.exercises.map(\.exerciseID))
                }
            }
            for template in templates {
                if let detail = fetchTemplate(id: template.id) {
                    collected.formUnion(detail.exercises.map(\.exerciseID))
                }
            }
            ids = collected
        }

        var names = exerciseNames
        for id in ids where names[id] == nil {
            if let summary = try? persistence.exercises.fetchSummary(id: id) {
                names[id] = summary.displayName
            }
        }
        exerciseNames = names
    }
}

enum WorkoutPersonalRecordFormatter {
    static func label(for record: DetectedPersonalRecord, exerciseName: String) -> String {
        switch record.metricType {
        case .maxWeight:
            "\(exerciseName): \(formatWeight(record.metricValue)) max weight"
        case .bestEstimated1RM:
            "\(exerciseName): \(formatWeight(record.metricValue)) e1RM"
        case .maxRepsAtWeight:
            "\(exerciseName): \(Int(record.metricValue)) reps PR"
        case .bestSetVolume, .bestSessionVolume:
            "\(exerciseName): volume PR"
        }
    }

    static func badgeText(for records: [DetectedPersonalRecord]) -> String {
        if records.contains(where: { $0.metricType == .bestEstimated1RM }) {
            return "e1RM PR"
        }
        if records.contains(where: { $0.metricType == .maxWeight }) {
            return "Weight PR"
        }
        if records.contains(where: { $0.metricType == .maxRepsAtWeight }) {
            return "Rep PR"
        }
        return "PR"
    }

    private static func formatWeight(_ kilograms: Double) -> String {
        kilograms.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f kg", kilograms)
            : String(format: "%.1f kg", kilograms)
    }
}

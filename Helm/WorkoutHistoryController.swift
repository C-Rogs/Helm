import Core
import Foundation
import HealthKitIngest
import Observation
import Persistence

enum WorkoutHistoryLoadState: Equatable {
    case idle
    case loadingInitial
    case loadingMore
    case loaded
}

@MainActor
@Observable
final class WorkoutHistoryController {
    private let persistence: PersistenceStore

    /// Active sessions for the current history-screen scope (Active or Bin).
    private(set) var sessions: [WorkoutSessionSummary] = []
    /// Always the newest active (non-deleted) page. Used by Train Recent so Bin scope never leaks.
    private(set) var activePreviewSessions: [WorkoutSessionSummary] = []
    private(set) var templates: [WorkoutTemplateSummary] = []
    private(set) var recentPersonalRecords: [DetectedPersonalRecord] = []
    private(set) var exerciseNames: [String: String] = [:]
    private(set) var loadState: WorkoutHistoryLoadState = .idle
    private(set) var activeCount = 0
    private(set) var deletedCount = 0
    private(set) var listScope: WorkoutSessionHistoryScope = .active

    var errorMessage: String?

    private let pageSize = 25
    private var loadedCount = 0
    private(set) var canLoadMore = true

    init(persistence: PersistenceStore) {
        self.persistence = persistence
    }

    func setListScope(_ scope: WorkoutSessionHistoryScope) {
        guard listScope != scope else { return }
        listScope = scope
        refresh()
    }

    func refresh() {
        loadState = .loadingInitial
        do {
            loadedCount = pageSize
            activeCount = try persistence.workoutSessions.countSummaries(scope: .active)
            deletedCount = try persistence.workoutSessions.countSummaries(scope: .deleted)
            let activePage = try persistence.workoutSessions.listSummaries(
                limit: pageSize,
                offset: 0,
                scope: .active
            )
            activePreviewSessions = activePage
            if listScope == .active {
                sessions = activePage
            } else {
                sessions = try persistence.workoutSessions.listSummaries(
                    limit: pageSize,
                    offset: 0,
                    scope: .deleted
                )
            }
            templates = try persistence.workoutTemplates.fetchSummaries()
            canLoadMore = sessions.count == pageSize
            refreshExerciseNames()
            errorMessage = nil
            loadState = .loaded
        } catch {
            errorMessage = error.localizedDescription
            loadState = .loaded
        }
    }

    func loadMoreIfNeeded(currentSessionID: String?) {
        guard canLoadMore, loadState != .loadingMore, let currentSessionID else { return }
        guard sessions.last?.id == currentSessionID else { return }

        loadState = .loadingMore
        do {
            let next = try persistence.workoutSessions.listSummaries(
                limit: pageSize,
                offset: loadedCount,
                scope: listScope
            )
            loadedCount += next.count
            sessions.append(contentsOf: next)
            canLoadMore = next.count == pageSize
            refreshExerciseNames()
            errorMessage = nil
            loadState = .loaded
        } catch {
            errorMessage = error.localizedDescription
            loadState = .loaded
        }
    }

    func fetchSession(id: String) -> WorkoutSessionDraft? {
        try? persistence.workoutSessions.fetch(id: id)
    }

    /// Synchronous stats + weekly landmarks for immediate history detail paint.
    func finishSummaryBase(for session: WorkoutSessionDraft) -> WorkoutFinishSummary? {
        SessionSummaryPresentationBuilder.base(session: session, store: persistence)
    }

    /// Full finish summary including timeline (HealthKit HR + markers + music).
    func finishSummary(for session: WorkoutSessionDraft) async -> WorkoutFinishSummary? {
        await SessionSummaryPresentationBuilder.build(session: session, store: persistence)
    }

    @discardableResult
    func saveSession(_ draft: WorkoutSessionDraft) -> Bool {
        do {
            try persistence.workoutSessions.updateCompletedSession(draft)
            refresh()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func deleteSession(id: String) -> Bool {
        do {
            try persistence.workoutSessions.delete(id: id)
            // Drop from active surfaces immediately so Recent never keeps a soft-deleted row.
            activePreviewSessions.removeAll { $0.id == id }
            if listScope == .active {
                sessions.removeAll { $0.id == id }
            }
            activeCount = max(0, activeCount - 1)
            deletedCount += 1
            refresh()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func restoreSession(id: String) -> Bool {
        do {
            try persistence.workoutSessions.restore(id: id)
            if listScope == .deleted {
                sessions.removeAll { $0.id == id }
            }
            deletedCount = max(0, deletedCount - 1)
            activeCount += 1
            refresh()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func createTemplate(from session: WorkoutSessionDraft, name: String) {
        do {
            _ = try persistence.workoutTemplates.createFromSession(session: session, name: name)
            templates = try persistence.workoutTemplates.fetchSummaries()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateTemplate(_ draft: WorkoutTemplateDraft) {
        do {
            try persistence.workoutTemplates.update(draft)
            templates = try persistence.workoutTemplates.fetchSummaries()
            refreshExerciseNames()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteTemplate(id: String) {
        do {
            try persistence.workoutTemplates.delete(id: id)
            templates = try persistence.workoutTemplates.fetchSummaries()
            errorMessage = nil
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

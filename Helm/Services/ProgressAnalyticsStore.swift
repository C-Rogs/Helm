import Core
import Foundation
import Observation
import Persistence

@Observable
@MainActor
final class ProgressAnalyticsStore {
    private(set) var snapshot = ProgressAnalyticsSnapshot.empty
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    var historyWindow: TrendsHistoryWindow = .days90 {
        didSet {
            guard historyWindow != oldValue else { return }
            refresh()
        }
    }

    private let store: PersistenceStore
    private let calendar: Calendar
    private let cutoff: DayCutoff
    private var reloadTask: Task<Void, Never>?
    private var reloadGeneration = 0

    init(
        store: PersistenceStore,
        calendar: Calendar = .current,
        cutoff: DayCutoff = .default
    ) {
        self.store = store
        self.calendar = calendar
        self.cutoff = cutoff
    }

    func refresh() {
        reloadGeneration &+= 1
        let generation = reloadGeneration
        let window = historyWindow
        let persistence = store
        let calendar = self.calendar
        let cutoff = self.cutoff

        isLoading = true
        errorMessage = nil

        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Self.compute(
                    window: window,
                    persistence: persistence,
                    calendar: calendar,
                    cutoff: cutoff
                )
            }.value

            guard let self, !Task.isCancelled, generation == reloadGeneration else { return }
            apply(result, window: window)
        }
    }

    private func apply(_ result: ReloadResult, window: TrendsHistoryWindow) {
        if let snapshot = result.snapshot {
            self.snapshot = snapshot
        } else {
            self.snapshot = ProgressAnalyticsSnapshot(
                window: window,
                overview: .empty,
                muscleDistribution: [],
                exerciseHighlights: []
            )
        }
        errorMessage = result.errorDescription
        isLoading = false
    }

    private struct ReloadResult: Sendable {
        var snapshot: ProgressAnalyticsSnapshot?
        var errorDescription: String?
    }

    private nonisolated static func compute(
        window: TrendsHistoryWindow,
        persistence: PersistenceStore,
        calendar: Calendar,
        cutoff: DayCutoff
    ) -> ReloadResult {
        do {
            let today = HelmDay.day(for: .now, cutoff: cutoff, calendar: calendar)
            let snapshot = try ProgressAnalyticsBuilder.build(
                store: persistence,
                window: window,
                endingAt: today,
                calendar: calendar,
                cutoff: cutoff
            )
            return ReloadResult(snapshot: snapshot, errorDescription: nil)
        } catch {
            return ReloadResult(snapshot: nil, errorDescription: error.localizedDescription)
        }
    }
}

enum ProgressAnalyticsBootstrap {
    @MainActor
    static let store = ProgressAnalyticsStore(store: PersistenceBootstrap.persistenceStore)
}

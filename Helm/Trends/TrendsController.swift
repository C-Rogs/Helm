import Core
import Foundation
import Observation
import Persistence

@MainActor
@Observable
final class TrendsController {
    private let persistence: PersistenceStore
    private let calendar: Calendar

    private(set) var snapshot = TrendsSnapshot.empty
    /// Dashboard default: recent window, not full lifetime history.
    var historyWindow: TrendsHistoryWindow = .days90
    var errorMessage: String?

    private var historyOffset = 0
    private var canLoadMore = true
    private var selectedExerciseID: String?
    private var reloadTask: Task<Void, Never>?

    init(persistence: PersistenceStore, calendar: Calendar = .current) {
        self.persistence = persistence
        self.calendar = calendar
    }

    func refresh() {
        historyOffset = 0
        canLoadMore = true
        scheduleReload(mode: .replace, coverWindow: true)
    }

    func setHistoryWindow(_ window: TrendsHistoryWindow) {
        guard historyWindow != window else { return }
        historyWindow = window
        if window == .all {
            return
        }
        coverSelectedWindowIfNeeded()
    }

    func loadMoreHistoryIfNeeded() {
        guard canLoadMore else { return }
        historyOffset += TrendsDataBuilder.pageSize
        scheduleReload(mode: .append, coverWindow: false)
    }

    func selectExercise(id: String) {
        selectedExerciseID = id
        scheduleReload(mode: .replace, coverWindow: true)
    }

    var displayedBodyWeight: [TrendWeightPoint] {
        windowedWeight(snapshot.bodyWeight)
    }

    var displayedTrendWeight: [TrendWeightPoint] {
        windowedWeight(snapshot.trendWeight)
    }

    var displayedE1RMHistory: [E1RMProgressionPoint] {
        let today = HelmDay.day(for: .now, calendar: calendar)
        return TrendsChartSupport.windowed(
            snapshot.e1RMHistory,
            window: historyWindow,
            today: today,
            calendar: calendar,
            day: \.helmDay
        )
    }

    private func windowedWeight(_ points: [TrendWeightPoint]) -> [TrendWeightPoint] {
        let today = HelmDay.day(for: .now, calendar: calendar)
        return TrendsChartSupport.windowed(
            points,
            window: historyWindow,
            today: today,
            calendar: calendar,
            day: \.helmDay
        )
    }

    private enum ReloadMode {
        case replace
        case append
        case none
    }

    /// Page in older samples until the selected window is covered (or history ends).
    private func coverSelectedWindowIfNeeded() {
        guard TrendsChartSupport.windowStart(
            for: historyWindow,
            today: HelmDay.day(for: .now, calendar: calendar),
            calendar: calendar
        ) != nil else {
            return
        }
        scheduleReload(mode: .none, coverWindow: true)
    }

    private func scheduleReload(mode: ReloadMode, coverWindow: Bool) {
        let persistence = self.persistence
        let calendar = self.calendar
        let preferredExerciseID = selectedExerciseID
        let startOffset = historyOffset
        let previousSnapshot = snapshot
        let window = coverWindow ? historyWindow : nil

        reloadTask?.cancel()
        reloadTask = Task(priority: .userInitiated) { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Self.computeReload(
                    persistence: persistence,
                    calendar: calendar,
                    preferredExerciseID: preferredExerciseID,
                    startOffset: startOffset,
                    mode: mode,
                    previousSnapshot: previousSnapshot,
                    coverWindow: window
                )
            }.value
            guard let self, !Task.isCancelled else { return }
            apply(result)
        }
    }

    private func apply(_ result: ReloadResult) {
        selectedExerciseID = result.selectedExerciseID
        if let snapshot = result.snapshot {
            self.snapshot = snapshot
            historyOffset = result.finalOffset
            canLoadMore = snapshot.canLoadMoreHistory
        }
        errorMessage = result.errorDescription
    }

    private struct ReloadResult: Sendable {
        var snapshot: TrendsSnapshot?
        var selectedExerciseID: String
        var finalOffset: Int
        var errorDescription: String?
    }

    private nonisolated static func computeReload(
        persistence: PersistenceStore,
        calendar: Calendar,
        preferredExerciseID: String?,
        startOffset: Int,
        mode: ReloadMode,
        previousSnapshot: TrendsSnapshot,
        coverWindow: TrendsHistoryWindow?
    ) -> ReloadResult {
        do {
            let exercise = try TrendsDataBuilder.resolveExercise(
                store: persistence,
                preferredID: preferredExerciseID
            )
            let today = HelmDay.day(for: .now, calendar: calendar)
            let settings = try persistence.trainingPlan.load()
            let targetKg = settings.phaseGoal.targetMass?.kilograms
            let muscleVolume = try TrendsDataBuilder.buildMuscleVolume(
                store: persistence,
                weekContaining: today,
                calendar: calendar
            )

            func fetchPage(at offset: Int) throws -> (
                bodyWeight: [TrendWeightPoint],
                trendWeight: [TrendWeightPoint],
                readiness: [ReadinessHistoryPoint],
                e1RM: [E1RMProgressionPoint],
                energy: [EnergyBalanceGauge],
                canLoadMore: Bool
            ) {
                let weightPage = try TrendsDataBuilder.buildTrendWeightPage(
                    store: persistence,
                    endingAt: today,
                    offset: offset,
                    targetWeightKg: targetKg,
                    calendar: calendar
                )
                let readinessPage = try TrendsDataBuilder.buildReadinessPage(
                    store: persistence,
                    endingAt: today,
                    offset: offset
                )
                let e1RMPage = try TrendsDataBuilder.buildE1RMPage(
                    store: persistence,
                    exerciseID: exercise.id,
                    offset: offset,
                    calendar: calendar
                )
                let energyPage = try TrendsDataBuilder.buildEnergyBalancePage(
                    store: persistence,
                    endingAt: today,
                    offset: offset,
                    calendar: calendar
                )
                return (
                    weightPage.bodyWeight,
                    weightPage.trendWeight,
                    readinessPage.points,
                    e1RMPage.points,
                    energyPage.gauges,
                    weightPage.canLoadMore
                        || readinessPage.canLoadMore
                        || e1RMPage.canLoadMore
                        || energyPage.canLoadMore
                )
            }

            var current: TrendsSnapshot
            var offset = startOffset

            switch mode {
            case .replace:
                let page = try fetchPage(at: 0)
                current = TrendsSnapshot(
                    bodyWeight: page.bodyWeight,
                    trendWeight: page.trendWeight,
                    targetWeightKg: targetKg,
                    readinessHistory: page.readiness,
                    muscleVolume: muscleVolume,
                    e1RMHistory: page.e1RM,
                    selectedExerciseID: exercise.id,
                    selectedExerciseName: exercise.name,
                    energyBalance: page.energy,
                    canLoadMoreHistory: page.canLoadMore
                )
            case .append:
                let page = try fetchPage(at: offset)
                current = TrendsSnapshot(
                    bodyWeight: mergeByID(previousSnapshot.bodyWeight, page.bodyWeight) { $0.helmDay },
                    trendWeight: mergeByID(previousSnapshot.trendWeight, page.trendWeight) { $0.helmDay },
                    targetWeightKg: targetKg,
                    readinessHistory: mergeByID(previousSnapshot.readinessHistory, page.readiness) { $0.helmDay },
                    muscleVolume: muscleVolume,
                    e1RMHistory: mergeByID(previousSnapshot.e1RMHistory, page.e1RM) { $0.achievedAt },
                    selectedExerciseID: exercise.id,
                    selectedExerciseName: exercise.name,
                    energyBalance: mergeByID(previousSnapshot.energyBalance, page.energy) { $0.helmDay },
                    canLoadMoreHistory: page.canLoadMore
                )
            case .none:
                current = previousSnapshot
            }

            if let window = coverWindow,
               let start = TrendsChartSupport.windowStart(
                   for: window,
                   today: today,
                   calendar: calendar
               )
            {
                var guardRails = 0
                while current.canLoadMoreHistory, guardRails < 20 {
                    guardRails += 1
                    try Task.checkCancellation()

                    let oldestWeight = current.trendWeight.first?.helmDay
                    let oldestE1RM = current.e1RMHistory.first?.helmDay
                    let oldest = [oldestWeight, oldestE1RM].compactMap { $0 }.min()

                    if let oldest, oldest <= start {
                        break
                    }
                    if oldest == nil, !current.canLoadMoreHistory {
                        break
                    }

                    offset += TrendsDataBuilder.pageSize
                    let page = try fetchPage(at: offset)
                    current = TrendsSnapshot(
                        bodyWeight: mergeByID(current.bodyWeight, page.bodyWeight) { $0.helmDay },
                        trendWeight: mergeByID(current.trendWeight, page.trendWeight) { $0.helmDay },
                        targetWeightKg: targetKg,
                        readinessHistory: mergeByID(current.readinessHistory, page.readiness) { $0.helmDay },
                        muscleVolume: muscleVolume,
                        e1RMHistory: mergeByID(current.e1RMHistory, page.e1RM) { $0.achievedAt },
                        selectedExerciseID: exercise.id,
                        selectedExerciseName: exercise.name,
                        energyBalance: mergeByID(current.energyBalance, page.energy) { $0.helmDay },
                        canLoadMoreHistory: page.canLoadMore
                    )
                }
            }

            return ReloadResult(
                snapshot: current,
                selectedExerciseID: exercise.id,
                finalOffset: offset,
                errorDescription: nil
            )
        } catch {
            return ReloadResult(
                snapshot: nil,
                selectedExerciseID: preferredExerciseID ?? "",
                finalOffset: startOffset,
                errorDescription: error.localizedDescription
            )
        }
    }

    private nonisolated static func mergeByID<Element>(
        _ existing: [Element],
        _ incoming: [Element],
        sortKey: (Element) -> some Comparable
    ) -> [Element] where Element: Identifiable {
        var seen = Set(existing.map(\.id))
        var merged = existing
        for item in incoming where seen.insert(item.id).inserted {
            merged.append(item)
        }
        return merged.sorted { sortKey($0) < sortKey($1) }
    }
}

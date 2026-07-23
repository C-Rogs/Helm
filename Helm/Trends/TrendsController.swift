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
    var errorMessage: String?

    private var historyOffset = 0
    private var canLoadMore = true
    private var selectedExerciseID: String?

    init(persistence: PersistenceStore, calendar: Calendar = .current) {
        self.persistence = persistence
        self.calendar = calendar
    }

    func refresh() {
        historyOffset = 0
        canLoadMore = true
        reload()
    }

    func loadMoreHistoryIfNeeded() {
        guard canLoadMore else { return }
        historyOffset += TrendsDataBuilder.pageSize
        reload(appendHistory: true)
    }

    func selectExercise(id: String) {
        selectedExerciseID = id
        reload()
    }

    private func reload(appendHistory: Bool = false) {
        do {
            let today = HelmDay.day(for: .now, calendar: calendar)
            let settings = try persistence.trainingPlan.load()
            let targetKg = settings.phaseGoal.targetMass?.kilograms
            let exercise = try TrendsDataBuilder.resolveExercise(
                store: persistence,
                preferredID: selectedExerciseID
            )
            selectedExerciseID = exercise.id

            let weightPage = try TrendsDataBuilder.buildTrendWeightPage(
                store: persistence,
                endingAt: today,
                offset: appendHistory ? historyOffset : 0,
                targetWeightKg: targetKg,
                calendar: calendar
            )
            let readinessPage = try TrendsDataBuilder.buildReadinessPage(
                store: persistence,
                endingAt: today,
                offset: appendHistory ? historyOffset : 0
            )
            let muscleVolume = try TrendsDataBuilder.buildMuscleVolume(
                store: persistence,
                weekContaining: today,
                calendar: calendar
            )
            let e1RMPage = try TrendsDataBuilder.buildE1RMPage(
                store: persistence,
                exerciseID: exercise.id,
                offset: appendHistory ? historyOffset : 0,
                calendar: calendar
            )
            let energyPage = try TrendsDataBuilder.buildEnergyBalancePage(
                store: persistence,
                endingAt: today,
                offset: appendHistory ? historyOffset : 0,
                calendar: calendar
            )

            if appendHistory {
                snapshot = TrendsSnapshot(
                    trendWeight: mergeTrendWeight(snapshot.trendWeight, weightPage.points),
                    targetWeightKg: targetKg,
                    readinessHistory: mergeReadiness(snapshot.readinessHistory, readinessPage.points),
                    muscleVolume: muscleVolume,
                    e1RMHistory: mergeE1RM(snapshot.e1RMHistory, e1RMPage.points),
                    selectedExerciseID: exercise.id,
                    selectedExerciseName: exercise.name,
                    energyBalance: mergeEnergy(snapshot.energyBalance, energyPage.gauges),
                    canLoadMoreHistory: weightPage.canLoadMore
                        || readinessPage.canLoadMore
                        || e1RMPage.canLoadMore
                        || energyPage.canLoadMore
                )
            } else {
                snapshot = TrendsSnapshot(
                    trendWeight: weightPage.points,
                    targetWeightKg: targetKg,
                    readinessHistory: readinessPage.points,
                    muscleVolume: muscleVolume,
                    e1RMHistory: e1RMPage.points,
                    selectedExerciseID: exercise.id,
                    selectedExerciseName: exercise.name,
                    energyBalance: energyPage.gauges,
                    canLoadMoreHistory: weightPage.canLoadMore
                        || readinessPage.canLoadMore
                        || e1RMPage.canLoadMore
                        || energyPage.canLoadMore
                )
            }

            canLoadMore = snapshot.canLoadMoreHistory
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func mergeTrendWeight(_ existing: [TrendWeightPoint], _ incoming: [TrendWeightPoint]) -> [TrendWeightPoint] {
        var seen = Set(existing.map(\.id))
        var merged = existing
        for item in incoming where seen.insert(item.id).inserted {
            merged.append(item)
        }
        return merged.sorted { $0.helmDay < $1.helmDay }
    }

    private func mergeReadiness(_ existing: [ReadinessHistoryPoint], _ incoming: [ReadinessHistoryPoint]) -> [ReadinessHistoryPoint] {
        var seen = Set(existing.map(\.id))
        var merged = existing
        for item in incoming where seen.insert(item.id).inserted {
            merged.append(item)
        }
        return merged.sorted { $0.helmDay < $1.helmDay }
    }

    private func mergeE1RM(_ existing: [E1RMProgressionPoint], _ incoming: [E1RMProgressionPoint]) -> [E1RMProgressionPoint] {
        var seen = Set(existing.map(\.id))
        var merged = existing
        for item in incoming where seen.insert(item.id).inserted {
            merged.append(item)
        }
        return merged.sorted { $0.achievedAt < $1.achievedAt }
    }

    private func mergeEnergy(_ existing: [EnergyBalanceGauge], _ incoming: [EnergyBalanceGauge]) -> [EnergyBalanceGauge] {
        var seen = Set(existing.map(\.id))
        var merged = existing
        for item in incoming where seen.insert(item.id).inserted {
            merged.append(item)
        }
        return merged.sorted { $0.helmDay < $1.helmDay }
    }
}

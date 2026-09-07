import Core
import DesignSystem
import Foundation

/// Builds `RecompStory` inputs from Trends + optional body-fat history.
enum RecompStoryBuilder {
    /// Absolute kg band treated as scale-flat over the comparison window.
    static let weightFlatKg: Double = 0.35
    /// Absolute e1RM kg band treated as flat.
    static let strengthFlatKg: Double = 1.5
    /// Body-fat percentage points treated as flat.
    static let bodyFatFlatPoints: Double = 0.4

    static func story(
        trendWeightKgOldestFirst: [Double],
        e1RMKgOldestFirst: [Double],
        volumeCompletionRatio: Double?,
        bodyFatPercentOldestFirst: [Double]
    ) -> RecompStory {
        let signals = RecompStorySignals(
            weight: RecompSignalMath.directionFromSeries(
                trendWeightKgOldestFirst,
                flatAbsolute: weightFlatKg
            ),
            strength: RecompSignalMath.directionFromSeries(
                e1RMKgOldestFirst,
                flatAbsolute: strengthFlatKg
            ),
            volume: volumeDirection(completionRatio: volumeCompletionRatio),
            bodyFat: RecompSignalMath.directionFromSeries(
                bodyFatPercentOldestFirst,
                flatAbsolute: bodyFatFlatPoints
            )
        )
        return RecompStoryClassifier.classify(signals)
    }

    static func story(
        snapshot: TrendsSnapshot,
        bodyFatPercentOldestFirst: [Double]
    ) -> RecompStory {
        let weight = windowPairValues(
            snapshot.trendWeight.map(\.trendWeightKg),
            preferRecentCount: 14
        )
        let e1rm = windowPairValues(
            snapshot.e1RMHistory.map(\.e1RMKilograms),
            preferRecentCount: 12
        )
        let volumeRatio = volumeCompletionRatio(from: snapshot.muscleVolume)
        return story(
            trendWeightKgOldestFirst: weight,
            e1RMKgOldestFirst: e1rm,
            volumeCompletionRatio: volumeRatio,
            bodyFatPercentOldestFirst: bodyFatPercentOldestFirst
        )
    }

    /// Prefer early vs late samples in a recent window so flat/rising is meaningful.
    static func windowPairValues(_ valuesOldestFirst: [Double], preferRecentCount: Int) -> [Double] {
        guard valuesOldestFirst.count >= 2 else { return valuesOldestFirst }
        let window = Array(valuesOldestFirst.suffix(max(preferRecentCount, 2)))
        guard let first = window.first, let last = window.last else { return [] }
        if window.count == 2 { return window }
        // Mid-anchor reduces noise when the window is long.
        let mid = window[window.count / 2]
        return [first, mid, last]
    }

    static func volumeCompletionRatio(from gauges: [MuscleVolumeGauge]) -> Double? {
        let targets = gauges.filter { $0.landmarks.mev > 0 || $0.scheduledSets > 0 || $0.weeklySets > 0 }
        guard !targets.isEmpty else { return nil }
        let ratios = targets.map { gauge -> Double in
            let target = max(gauge.scheduledSets + gauge.weeklySets, Double(gauge.landmarks.mev), 1)
            return gauge.weeklySets / target
        }
        return ratios.reduce(0, +) / Double(ratios.count)
    }

    static func volumeDirection(completionRatio: Double?) -> RecompSignalDirection {
        guard let completionRatio, completionRatio.isFinite else { return .unknown }
        if completionRatio >= 1.05 { return .rising }
        if completionRatio >= 0.75 { return .flat }
        if completionRatio >= 0.35 { return .falling }
        return .falling
    }
}

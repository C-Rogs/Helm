import Core
import Foundation
import ReadinessKit
import ReadinessKit

/// Edwards TRIMP from an observed workout and its heart-rate samples.
public enum WorkoutTRIMPCalculator: Sendable {
    public struct Result: Sendable, Equatable {
        public let workoutDay: HelmDay
        public let targetDay: HelmDay
        public let trimp: Double

        public init(workoutDay: HelmDay, targetDay: HelmDay, trimp: Double) {
            self.workoutDay = workoutDay
            self.targetDay = targetDay
            self.trimp = trimp
        }
    }

    public static func trimp(
        for workout: IngestWorkoutSample,
        heartRateSamples: [Double],
        restingHeartRate: Double,
        calendar: Calendar = .current,
        cutoff: DayCutoff = .default
    ) -> Result? {
        guard !heartRateSamples.isEmpty else { return nil }

        let workoutDay = HelmDay.day(for: workout.end, cutoff: cutoff, calendar: calendar)
        let targetDay = workoutDay.adding(days: 1, calendar: calendar)
        let hrMax = StrainCalculator.hrMax(observedHRSamples: heartRateSamples, age: nil)
        let trimp = StrainCalculator.edwardsTRIMP(
            heartRateSamples: heartRateSamples,
            restingHR: restingHeartRate,
            hrMax: hrMax
        )

        guard trimp > 0 else { return nil }

        return Result(workoutDay: workoutDay, targetDay: targetDay, trimp: trimp)
    }

    public static func mergedTRIMPByTargetDay(_ results: [Result]) -> [HelmDay: Double] {
        results.reduce(into: [:]) { totals, result in
            totals[result.targetDay, default: 0] += result.trimp
        }
    }
}

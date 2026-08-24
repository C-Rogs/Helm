import Core
import Foundation
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
        heartRateReadings: [(date: Date, bpm: Double)],
        restingHeartRate: Double,
        athleteAgeYears: Int?,
        calendar: Calendar = .current,
        cutoff: DayCutoff = .default
    ) -> Result? {
        guard !heartRateReadings.isEmpty else { return nil }

        let workoutDay = HelmDay.day(for: workout.end, cutoff: cutoff, calendar: calendar)
        let targetDay = workoutDay.adding(days: 1, calendar: calendar)
        let bpms = heartRateReadings.map(\.bpm)
        let hrMax = StrainCalculator.hrMax(observedHRSamples: bpms, age: athleteAgeYears)
        let trimp = StrainCalculator.edwardsTRIMP(
            datedHeartRateReadings: heartRateReadings,
            workoutStart: workout.start,
            workoutEnd: workout.end,
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

import Core
import Foundation
import NutritionKit
import PlanKit
import Testing
@testable import HealthKitIngest

@Suite("Nutrition day type resolver")
struct NutritionDayTypeResolverTests {
    @Test("rest day when no prescription volume")
    func restDay() {
        let dayType = NutritionDayTypeResolver.resolve(
            prescriptionSummary: nil,
            targetMuscles: [.chest],
            mesocycleState: nil
        )
        #expect(dayType == .rest)
    }

    @Test("training day when session has sets")
    func trainingDay() {
        let summary = PrescribedSessionSummary(
            phase: .maintain,
            emphasis: nil,
            exercises: [],
            totalSets: 12,
            readinessAdjusted: false
        )
        let dayType = NutritionDayTypeResolver.resolve(
            prescriptionSummary: summary,
            targetMuscles: [.chest],
            mesocycleState: nil
        )
        #expect(dayType == .training)
    }

    @Test("deload day when target muscle is deloading")
    func deloadDay() {
        let summary = PrescribedSessionSummary(
            phase: .maintain,
            emphasis: nil,
            exercises: [],
            totalSets: 8,
            readinessAdjusted: false
        )
        let landmarks = VolumeLandmarks(mev: 8, mrv: 22)
        let mesocycle = MesocycleState(muscles: [
            .chest: MuscleMesocycleState(landmarks: landmarks, blockLengthWeeks: 4, currentWeek: 4),
        ])

        let dayType = NutritionDayTypeResolver.resolve(
            prescriptionSummary: summary,
            targetMuscles: [.chest],
            mesocycleState: mesocycle
        )
        #expect(dayType == .deload)
    }
}

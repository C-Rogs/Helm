import Core
import Testing
@testable import HealthKitIngest

@Suite("NutritionTargetComposer")
struct NutritionTargetComposerTests {
    @Test("phase shifts calorie target")
    func phaseShift() {
        let cut = NutritionTargetComposer.compose(phase: .cut, bodyMassKg: 80, isTrainingDay: true)
        let gain = NutritionTargetComposer.compose(phase: .gain, bodyMassKg: 80, isTrainingDay: true)

        #expect(cut.caloriesKcal < gain.caloriesKcal)
        #expect(cut.proteinGrams == 160)
    }

    @Test("training day allocates more carbs than rest day")
    func dayTypePeriodisation() {
        let training = NutritionTargetComposer.compose(phase: .maintain, bodyMassKg: 75, isTrainingDay: true)
        let rest = NutritionTargetComposer.compose(phase: .maintain, bodyMassKg: 75, isTrainingDay: false)

        #expect(training.carbohydrateGrams > rest.carbohydrateGrams)
        #expect(training.dayType == "training")
        #expect(rest.dayType == "rest")
    }
}

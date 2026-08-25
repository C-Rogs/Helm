import Core
import Testing
@testable import NutritionKit

@Suite("Weekly nutrition budget")
struct WeeklyNutritionBudgetTests {
    let monday = HelmDay(year: 2026, month: 8, day: 24)
    let demands: [WeeklyNutritionDemand] = [.heavyLift, .restOffice, .lightLift, .cardio, .heavyLift, .social, .restOffice]

    func inputs(consumed: [Int: Int] = [:]) -> [WeeklyNutritionBudgetDayInput] {
        demands.indices.map { WeeklyNutritionBudgetDayInput(day: monday.adding(days: $0), demand: demands[$0], consumedCaloriesKcal: consumed[$0]) }
    }

    @Test("allocates Monday through Sunday and preserves exact weekly calories")
    func canonicalAllocation() {
        let budget = WeeklyNutritionBudgetCalculator.calculate(weekStart: monday, weeklyCaloriesKcal: 17_503, proteinGramsPerDay: 160, days: inputs())
        #expect(budget.days.map(\.day) == (0 ..< 7).map { monday.adding(days: $0) })
        #expect(budget.allocatedCaloriesKcal == 17_503)
        #expect(budget.excessCaloriesKcal == 0)
        #expect(budget.days[0].caloriesKcal > budget.days[1].caloriesKcal)
        #expect(budget.days[5].caloriesKcal > budget.days[6].caloriesKcal)
    }

    @Test("protein remains stable while carbohydrates carry demand variation")
    func carbFirstVariation() {
        let budget = WeeklyNutritionBudgetCalculator.calculate(weekStart: monday, weeklyCaloriesKcal: 17_500, proteinGramsPerDay: 160, days: inputs())
        #expect(Set(budget.days.map(\.proteinGrams)) == [160])
        #expect(budget.days[0].carbohydrateGrams > budget.days[1].carbohydrateGrams)
        #expect(budget.days[0].fatGrams >= 40)
        #expect(budget.days[1].fatGrams >= 40)
    }

    @Test("consumed days lock and remaining future days reflow deterministically")
    func futureReflow() {
        let budget = WeeklyNutritionBudgetCalculator.calculate(weekStart: monday, weeklyCaloriesKcal: 17_500, proteinGramsPerDay: 160, days: inputs(consumed: [0: 3_000, 1: 2_000]), asOf: monday.adding(days: 2))
        #expect(budget.days[0].state == .consumed)
        #expect(budget.days[1].state == .consumed)
        #expect(budget.days[2].state == .remaining)
        #expect(budget.days[3].state == .provisional)
        #expect(budget.days[2...].allSatisfy { $0.reason == .futureReflow })
        #expect(budget.allocatedCaloriesKcal == 17_500)
        #expect(budget.consumedCaloriesKcal == 5_000)
        #expect(budget.remainingCaloriesKcal == 12_500)
    }

    @Test("future reflow respects floor")
    func safeFloor() {
        let constraints = WeeklyNutritionBudgetCalculator.Constraints(minimumDailyCaloriesKcal: 1_500, maximumDailyCaloriesKcal: 4_000)
        let budget = WeeklyNutritionBudgetCalculator.calculate(weekStart: monday, weeklyCaloriesKcal: 10_000, proteinGramsPerDay: 140, days: inputs(consumed: [0: 4_000, 1: 4_000, 2: 1_000]), asOf: monday.adding(days: 3), constraints: constraints)
        #expect(budget.days[3...].allSatisfy { $0.caloriesKcal >= 1_500 })
        #expect(budget.days[3...].allSatisfy { $0.reason == .constrainedByFloor })
    }

    @Test("future cap leaves visible excess instead of hiding calories")
    func capAndExcess() {
        let constraints = WeeklyNutritionBudgetCalculator.Constraints(minimumDailyCaloriesKcal: 1_200, maximumDailyCaloriesKcal: 2_000)
        let budget = WeeklyNutritionBudgetCalculator.calculate(weekStart: monday, weeklyCaloriesKcal: 20_000, proteinGramsPerDay: 160, days: inputs(consumed: [0: 3_000, 1: 3_000, 2: 3_000, 3: 3_000, 4: 3_000]), asOf: monday.adding(days: 5), constraints: constraints)
        #expect(budget.days[5].caloriesKcal == 2_000)
        #expect(budget.days[6].caloriesKcal == 2_000)
        #expect(budget.excessCaloriesKcal == 1_000)
        #expect(budget.days[5...].allSatisfy { $0.reason == .constrainedByCap })
    }

    @Test("overconsumption is visible when no future capacity exists")
    func consumedExcess() {
        let consumed = Dictionary(uniqueKeysWithValues: (0 ..< 7).map { ($0, 3_000) })
        let budget = WeeklyNutritionBudgetCalculator.calculate(weekStart: monday, weeklyCaloriesKcal: 17_500, proteinGramsPerDay: 160, days: inputs(consumed: consumed), asOf: monday.adding(days: 6))
        #expect(budget.excessCaloriesKcal == 3_500)
        #expect(budget.remainingCaloriesKcal == 0)
        #expect(budget.days.allSatisfy { $0.state == .consumed })
    }

    @Test("missing and unordered inputs still yield deterministic canonical week")
    func normalizesInputs() {
        let sparse = [
            WeeklyNutritionBudgetDayInput(day: monday.adding(days: 6), demand: .social),
            WeeklyNutritionBudgetDayInput(day: monday, demand: .heavyLift)
        ]
        let first = WeeklyNutritionBudgetCalculator.calculate(weekStart: monday, weeklyCaloriesKcal: 14_000, proteinGramsPerDay: 150, days: sparse)
        let second = WeeklyNutritionBudgetCalculator.calculate(weekStart: monday, weeklyCaloriesKcal: 14_000, proteinGramsPerDay: 150, days: sparse.reversed())
        #expect(first == second)
        #expect(first.days.count == 7)
        #expect(first.days[1].demand == .rest)
    }

    // MARK: - Invariants

    @Test("allocatedCaloriesKcal never exceeds targetCaloriesKcal")
    func allocatedNeverExceedsTarget() {
        for target in [10_000, 14_000, 17_500, 21_000, 24_500] {
            let budget = WeeklyNutritionBudgetCalculator.calculate(weekStart: monday, weeklyCaloriesKcal: target, proteinGramsPerDay: 160, days: inputs())
            #expect(budget.allocatedCaloriesKcal <= target)
        }

        // With consumed days and reflow.
        let withConsumed = WeeklyNutritionBudgetCalculator.calculate(
            weekStart: monday, weeklyCaloriesKcal: 17_500, proteinGramsPerDay: 160,
            days: inputs(consumed: [0: 3_000, 1: 2_500]),
            asOf: monday.adding(days: 2)
        )
        #expect(withConsumed.allocatedCaloriesKcal <= 17_500)

        // With cap constraint.
        let constraints = WeeklyNutritionBudgetCalculator.Constraints(minimumDailyCaloriesKcal: 1_200, maximumDailyCaloriesKcal: 2_000)
        let withCap = WeeklyNutritionBudgetCalculator.calculate(
            weekStart: monday, weeklyCaloriesKcal: 20_000, proteinGramsPerDay: 160,
            days: inputs(consumed: [0: 3_000, 1: 3_000, 2: 3_000, 3: 3_000, 4: 3_000]),
            asOf: monday.adding(days: 5),
            constraints: constraints
        )
        #expect(withCap.allocatedCaloriesKcal <= 20_000)
    }

    @Test("all seven days have non-negative calories")
    func allDaysNonNegative() {
        let budget = WeeklyNutritionBudgetCalculator.calculate(weekStart: monday, weeklyCaloriesKcal: 17_500, proteinGramsPerDay: 160, days: inputs())
        #expect(budget.days.count == 7)
        #expect(budget.days.allSatisfy { $0.caloriesKcal >= 0 })

        // Even with consumed days exceeding target.
        let consumed = Dictionary(uniqueKeysWithValues: (0 ..< 7).map { ($0, 3_500) })
        let excess = WeeklyNutritionBudgetCalculator.calculate(
            weekStart: monday, weeklyCaloriesKcal: 17_500, proteinGramsPerDay: 160,
            days: inputs(consumed: consumed),
            asOf: monday.adding(days: 6)
        )
        #expect(excess.days.allSatisfy { $0.caloriesKcal >= 0 })
    }

    @Test("protein is identical across all seven days")
    func proteinIdenticalAcrossDays() {
        let budget = WeeklyNutritionBudgetCalculator.calculate(weekStart: monday, weeklyCaloriesKcal: 17_500, proteinGramsPerDay: 160, days: inputs())
        #expect(Set(budget.days.map(\.proteinGrams)).count == 1)
        #expect(budget.days.first?.proteinGrams == 160)
    }

    @Test("consumed days' caloriesKcal matches the consumedCaloriesKcal input")
    func consumedCaloriesMatchInput() {
        let consumed: [Int: Int] = [0: 3_000, 1: 2_200, 2: 1_800]
        let budget = WeeklyNutritionBudgetCalculator.calculate(
            weekStart: monday, weeklyCaloriesKcal: 17_500, proteinGramsPerDay: 160,
            days: inputs(consumed: consumed),
            asOf: monday.adding(days: 3)
        )
        #expect(budget.days[0].state == .consumed)
        #expect(budget.days[0].caloriesKcal == 3_000)
        #expect(budget.days[0].consumedCaloriesKcal == 3_000)
        #expect(budget.days[1].state == .consumed)
        #expect(budget.days[1].caloriesKcal == 2_200)
        #expect(budget.days[1].consumedCaloriesKcal == 2_200)
        #expect(budget.days[2].state == .consumed)
        #expect(budget.days[2].caloriesKcal == 1_800)
        #expect(budget.days[2].consumedCaloriesKcal == 1_800)
    }

    @Test("unlogged past days keep demand allocation instead of locking at zero")
    func unloggedPastKeepsEstimate() {
        let budget = WeeklyNutritionBudgetCalculator.calculate(
            weekStart: monday,
            weeklyCaloriesKcal: 17_500,
            proteinGramsPerDay: 160,
            days: inputs(consumed: [2: 2_400]),
            asOf: monday.adding(days: 3)
        )
        #expect(budget.days[0].consumedCaloriesKcal == nil)
        #expect(budget.days[1].consumedCaloriesKcal == nil)
        #expect(budget.days[0].caloriesKcal > 0)
        #expect(budget.days[1].caloriesKcal > 0)
        #expect(budget.days[0].state == .provisional)
        #expect(budget.days[2].state == .consumed)
        #expect(budget.days[2].caloriesKcal == 2_400)
        #expect(budget.consumedCaloriesKcal == 2_400)
        #expect(budget.days[0].caloriesKcal > budget.days[1].caloriesKcal)
    }
}

import Core
import Foundation

public enum WeeklyNutritionDemand: String, Sendable, Hashable, Codable, CaseIterable {
    case heavyLift, lightLift, cardio, rest, restOffice, social, party, highIntake
}

extension WeeklyNutritionDemand {
    /// Maps the canonical NutritionDayDemand (already resolved with override >
    /// planned training > planned cardio > ordinary) into a weekly-budget
    /// demand type for calorie/macro allocation.
    public init(resolved demand: NutritionDayDemand) {
        switch demand {
        case .training: self = .heavyLift
        case .cardio: self = .cardio
        case .social: self = .social
        case .party: self = .party
        case .highIntake: self = .highIntake
        case .office: self = .restOffice
        case .ordinary: self = .rest
        }
    }
}

extension NutritionDayDemand {
    /// Convenience bridge so callers can produce budget demand directly.
    public var weeklyDemand: WeeklyNutritionDemand { WeeklyNutritionDemand(resolved: self) }
}

public enum WeeklyNutritionBudgetReason: String, Sendable, Hashable, Codable {
    case plannedDemand, consumed, futureReflow, constrainedByFloor, constrainedByCap
}

public enum WeeklyNutritionBudgetDayState: String, Sendable, Hashable, Codable {
    case consumed, remaining, provisional
}

public struct WeeklyNutritionBudgetDayInput: Sendable, Hashable, Codable, Equatable {
    public let day: HelmDay
    public let demand: WeeklyNutritionDemand
    public let consumedCaloriesKcal: Int?
    public init(day: HelmDay, demand: WeeklyNutritionDemand, consumedCaloriesKcal: Int? = nil) {
        self.day = day; self.demand = demand; self.consumedCaloriesKcal = consumedCaloriesKcal
    }
}

public struct WeeklyNutritionBudgetDay: Sendable, Hashable, Codable, Equatable, Identifiable {
    public var id: HelmDay { day }
    public let day: HelmDay
    public let demand: WeeklyNutritionDemand
    public let reason: WeeklyNutritionBudgetReason
    public let state: WeeklyNutritionBudgetDayState
    public let caloriesKcal: Int
    public let proteinGrams: Int
    public let carbohydrateGrams: Int
    public let fatGrams: Int
    public let consumedCaloriesKcal: Int?
    public let remainingCaloriesKcal: Int
    public var isProvisional: Bool { state == .provisional }
}

public struct WeeklyNutritionBudget: Sendable, Hashable, Codable, Equatable {
    public let weekStart: HelmDay
    public let targetCaloriesKcal: Int
    public let days: [WeeklyNutritionBudgetDay]
    public let consumedCaloriesKcal: Int
    public let remainingCaloriesKcal: Int
    public let excessCaloriesKcal: Int
    public var allocatedCaloriesKcal: Int { days.reduce(0) { $0 + $1.caloriesKcal } }
}

public enum WeeklyNutritionBudgetCalculator {
    public struct Constraints: Sendable, Hashable, Codable, Equatable {
        public let minimumDailyCaloriesKcal: Int
        public let maximumDailyCaloriesKcal: Int
        public let minimumFatGrams: Int
        public init(minimumDailyCaloriesKcal: Int = 1_200, maximumDailyCaloriesKcal: Int = 4_500, minimumFatGrams: Int = 40) {
            self.minimumDailyCaloriesKcal = max(minimumDailyCaloriesKcal, 0)
            self.maximumDailyCaloriesKcal = max(maximumDailyCaloriesKcal, self.minimumDailyCaloriesKcal)
            self.minimumFatGrams = max(minimumFatGrams, 0)
        }
    }

    public static func calculate(weekStart: HelmDay, weeklyCaloriesKcal: Int, proteinGramsPerDay: Int, days inputs: [WeeklyNutritionBudgetDayInput], asOf: HelmDay? = nil, constraints: Constraints = Constraints()) -> WeeklyNutritionBudget {
        let ordered = canonicalInputs(weekStart: weekStart, inputs: inputs)
        let weeklyTarget = max(weeklyCaloriesKcal, 0)
        let protein = max(proteinGramsPerDay, 0)
        let consumedByIndex = ordered.map { max($0.consumedCaloriesKcal ?? 0, 0) }
        // Only logged intake locks a day. Unlogged past days keep their demand
        // allocation so a missing diary does not dump those calories onto remaining days.
        let isLocked = ordered.map { $0.consumedCaloriesKcal != nil }
        let lockedTotal = zip(consumedByIndex, isLocked).reduce(0) { $0 + ($1.1 ? $1.0 : 0) }
        let futureIndices = ordered.indices.filter { !isLocked[$0] }
        let allocation = allocate(total: max(weeklyTarget - lockedTotal, 0), indices: futureIndices, demands: ordered.map(\.demand), floor: constraints.minimumDailyCaloriesKcal, cap: constraints.maximumDailyCaloriesKcal)
        var targets = consumedByIndex
        for (index, value) in allocation.values { targets[index] = value }

        let days = ordered.indices.map { index in
            let input = ordered[index], target = targets[index]
            let consumed = input.consumedCaloriesKcal.map { max($0, 0) }
            let state: WeeklyNutritionBudgetDayState
            if consumed != nil {
                state = .consumed
            } else if asOf.map({ input.day == $0 }) == true {
                state = .remaining
            } else {
                state = .provisional
            }
            let reason: WeeklyNutritionBudgetReason
            if consumed != nil { reason = .consumed }
            else if allocation.hitFloor.contains(index) { reason = .constrainedByFloor }
            else if allocation.hitCap.contains(index) { reason = .constrainedByCap }
            else if lockedTotal > 0 { reason = .futureReflow }
            else { reason = .plannedDemand }
            let macros = macroAllocation(calories: target, proteinGrams: protein, minimumFatGrams: constraints.minimumFatGrams, demand: input.demand)
            return WeeklyNutritionBudgetDay(day: input.day, demand: input.demand, reason: reason, state: state, caloriesKcal: target, proteinGrams: protein, carbohydrateGrams: macros.carbs, fatGrams: macros.fat, consumedCaloriesKcal: consumed, remainingCaloriesKcal: max(target - (consumed ?? 0), 0))
        }
        let consumedTotal = consumedByIndex.reduce(0, +)
        return WeeklyNutritionBudget(weekStart: weekStart, targetCaloriesKcal: weeklyTarget, days: days, consumedCaloriesKcal: consumedTotal, remainingCaloriesKcal: max(weeklyTarget - consumedTotal, 0), excessCaloriesKcal: max(lockedTotal - weeklyTarget, 0) + allocation.unallocated)
    }

    private static func canonicalInputs(weekStart: HelmDay, inputs: [WeeklyNutritionBudgetDayInput]) -> [WeeklyNutritionBudgetDayInput] {
        let byDay = Dictionary(inputs.map { ($0.day, $0) }, uniquingKeysWith: { _, last in last })
        return (0 ..< 7).map { offset in let day = weekStart.adding(days: offset); return byDay[day] ?? WeeklyNutritionBudgetDayInput(day: day, demand: .rest) }
    }

    private struct Allocation { var values: [Int: Int] = [:]; var hitFloor: Set<Int> = []; var hitCap: Set<Int> = []; var unallocated = 0 }

    private static func allocate(total: Int, indices: [Int], demands: [WeeklyNutritionDemand], floor: Int, cap: Int) -> Allocation {
        guard !indices.isEmpty else { return Allocation(unallocated: total) }
        let minimumTotal = floor * indices.count, maximumTotal = cap * indices.count
        let allocatable = min(max(total, minimumTotal), maximumTotal)
        let weightTotal = indices.reduce(0.0) { $0 + demandWeight(demands[$1]) }
        var result = Allocation(unallocated: max(total - maximumTotal, 0))
        var values = indices.map { max(floor, min(cap, Int((Double(allocatable) * demandWeight(demands[$0]) / weightTotal).rounded(.down)))) }
        var difference = allocatable - values.reduce(0, +)
        while difference != 0 {
            var changed = false
            for position in values.indices where difference != 0 {
                if difference > 0, values[position] < cap { values[position] += 1; difference -= 1; changed = true }
                else if difference < 0, values[position] > floor { values[position] -= 1; difference += 1; changed = true }
            }
            if !changed { break }
        }
        for (position, index) in indices.enumerated() {
            result.values[index] = values[position]
            if values[position] == floor, total <= minimumTotal { result.hitFloor.insert(index) }
            if values[position] == cap { result.hitCap.insert(index) }
        }
        return result
    }

    private static func demandWeight(_ demand: WeeklyNutritionDemand) -> Double {
        switch demand { case .heavyLift: 1.16; case .lightLift: 1.07; case .cardio: 1.04; case .social: 1.10; case .party: 1.14; case .highIntake: 1.12; case .restOffice: 1.05; case .rest: 0.86 }
    }

    private static func macroAllocation(calories: Int, proteinGrams: Int, minimumFatGrams: Int, demand: WeeklyNutritionDemand) -> (carbs: Int, fat: Int) {
        let available = max(calories - proteinGrams * 4, 0), fatFloorCalories = min(available, minimumFatGrams * 9)
        let flexible = max(available - fatFloorCalories, 0)
        let carbShare: Double
        switch demand { case .heavyLift: carbShare = 0.88; case .lightLift: carbShare = 0.78; case .cardio: carbShare = 0.82; case .social: carbShare = 0.70; case .party: carbShare = 0.64; case .highIntake: carbShare = 0.72; case .restOffice: carbShare = 0.62; case .rest: carbShare = 0.58 }
        let carbCalories = Int((Double(flexible) * carbShare).rounded(.down))
        return (carbCalories / 4, (available - carbCalories) / 9)
    }
}

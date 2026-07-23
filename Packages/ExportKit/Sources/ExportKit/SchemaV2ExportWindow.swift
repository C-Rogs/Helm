import Foundation

public struct SchemaV2ExportWindow: Equatable, Sendable {
    public var start: Date
    public var end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    public var isValid: Bool { start <= end }

    public var dayCount: Int {
        let calendar = Self.localCalendar()
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        let components = calendar.dateComponents([.day], from: startDay, to: endDay)
        return (components.day ?? 0) + 1
    }

    public static func localCalendar() -> Calendar {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        return calendar
    }

    public static func defaultWindow(calendar: Calendar = localCalendar()) -> SchemaV2ExportWindow {
        let today = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        return SchemaV2ExportWindow(start: start, end: today)
    }
}

public struct MetricInclusion: Codable, Equatable, Sendable {
    public var hrvToday = true
    public var rhrToday = true
    public var sleepTotal = true
    public var sleepDeep = true
    public var sleepREM = true
    public var weight = true
    public var bodyFat = true
    public var stepCount = true
    public var activeEnergy = true
    public var restingEnergy = true
    public var exerciseMinutes = true
    public var workouts = true
    public var trainingLoad = true
    public var caloriesConsumed = true
    public var proteinG = true
    public var carbsG = true
    public var fatG = true
    public var waterLiters = true
    public var alcoholicBeveragesCount = true

    public init() {}

    public var needsHRV: Bool { hrvToday }
    public var needsRHR: Bool { rhrToday }
    public var needsSleep: Bool { sleepTotal || sleepDeep || sleepREM }
    public var needsActivity: Bool {
        stepCount || activeEnergy || restingEnergy || exerciseMinutes || workouts || trainingLoad
    }
    public var needsNutrition: Bool {
        caloriesConsumed || proteinG || carbsG || fatG || waterLiters || alcoholicBeveragesCount
    }
}

public struct SchemaV2SleepSeries: Sendable, Equatable {
    public let total: [Date: Double?]
    public let deep: [Date: Double?]
    public let rem: [Date: Double?]

    public init(total: [Date: Double?], deep: [Date: Double?], rem: [Date: Double?]) {
        self.total = total
        self.deep = deep
        self.rem = rem
    }
}

/// Portable per-day metric maps keyed by start-of-day `Date`.
public struct SchemaV2MetricBundle: Sendable {
    public var hrv: [Date: Double?]
    public var rhr: [Date: Double?]
    public var sleep: SchemaV2SleepSeries
    public var steps: [Date: Double?]
    public var weight: [Date: Double?]
    public var bodyFat: [Date: Double?]
    public var activeEnergy: [Date: Double?]
    public var restingEnergy: [Date: Double?]
    public var exerciseMinutes: [Date: Double?]
    public var calories: [Date: Double?]
    public var protein: [Date: Double?]
    public var carbs: [Date: Double?]
    public var fat: [Date: Double?]
    public var water: [Date: Double?]
    public var alcohol: [Date: Double?]
    public var workouts: [Date: [WorkoutLog]]
    public var trainingLoad: [Date: Double?]

    public init(
        hrv: [Date: Double?] = [:],
        rhr: [Date: Double?] = [:],
        sleep: SchemaV2SleepSeries = SchemaV2SleepSeries(total: [:], deep: [:], rem: [:]),
        steps: [Date: Double?] = [:],
        weight: [Date: Double?] = [:],
        bodyFat: [Date: Double?] = [:],
        activeEnergy: [Date: Double?] = [:],
        restingEnergy: [Date: Double?] = [:],
        exerciseMinutes: [Date: Double?] = [:],
        calories: [Date: Double?] = [:],
        protein: [Date: Double?] = [:],
        carbs: [Date: Double?] = [:],
        fat: [Date: Double?] = [:],
        water: [Date: Double?] = [:],
        alcohol: [Date: Double?] = [:],
        workouts: [Date: [WorkoutLog]] = [:],
        trainingLoad: [Date: Double?] = [:]
    ) {
        self.hrv = hrv
        self.rhr = rhr
        self.sleep = sleep
        self.steps = steps
        self.weight = weight
        self.bodyFat = bodyFat
        self.activeEnergy = activeEnergy
        self.restingEnergy = restingEnergy
        self.exerciseMinutes = exerciseMinutes
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.water = water
        self.alcohol = alcohol
        self.workouts = workouts
        self.trainingLoad = trainingLoad
    }
}

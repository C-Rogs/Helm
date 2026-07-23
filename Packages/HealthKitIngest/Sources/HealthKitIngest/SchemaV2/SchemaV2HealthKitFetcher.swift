import ExportKit
import Foundation
import HealthKit

import HealthKit

public actor SchemaV2HealthKitFetcher {
    public init() {}

    /// Minimum workout duration included in exports.
    static let minimumWorkoutDurationMinutes = 5.0
    static let maxConcurrentMetricJobs = 4

    private let healthStore = HKHealthStore()
    private let hasRequestedAuthKey = "helm.schemaV2.hasRequestedHealthAuth"

    private static let readTypes: Set<HKObjectType> = {
        var types = Set<HKObjectType>()
        let quantityIds: [HKQuantityTypeIdentifier] = [
            .heartRateVariabilitySDNN,
            .restingHeartRate,
            .bodyMass,
            .bodyFatPercentage,
            .stepCount,
            .activeEnergyBurned,
            .basalEnergyBurned,
            .dietaryEnergyConsumed,
            .dietaryProtein,
            .dietaryCarbohydrates,
            .dietaryFatTotal,
            .dietaryWater,
            .numberOfAlcoholicBeverages,
            .appleExerciseTime,
            .workoutEffortScore
        ]
        for id in quantityIds {
            if let type = HKQuantityType.quantityType(forIdentifier: id) {
                types.insert(type)
            }
        }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        types.insert(HKObjectType.workoutType())
        return types
    }()

    public func requestAuthorization() async -> SchemaV2AuthResult {
        guard HKHealthStore.isHealthDataAvailable() else {
            return .unavailable
        }

        let requestStatus = await fetchRequestStatus()

        if requestStatus == .shouldRequest {
            do {
                try await healthStore.requestAuthorization(toShare: [], read: Self.readTypes)
                UserDefaults.standard.set(true, forKey: hasRequestedAuthKey)
            } catch {
                return .error
            }
            return .notDetermined
        }

        if !UserDefaults.standard.bool(forKey: hasRequestedAuthKey) {
            do {
                try await healthStore.requestAuthorization(toShare: [], read: Self.readTypes)
                UserDefaults.standard.set(true, forKey: hasRequestedAuthKey)
            } catch {
                return .error
            }
        }

        return .liveAuthorized
    }

    private func fetchRequestStatus() async -> HKAuthorizationRequestStatus {
        await withCheckedContinuation { continuation in
            healthStore.getRequestStatusForAuthorization(toShare: [], read: Self.readTypes) { status, _ in
                continuation.resume(returning: status)
            }
        }
    }

    public func fetchDailyLogs(
        window: SchemaV2ExportWindow,
        inclusion: MetricInclusion
    ) async throws -> [DailyLog] {
        try Task.checkCancellation()
        let calendar = localCalendar()
        let rangeStart = startOfCalendarDay(window.start, calendar: calendar)
        let rangeEndDay = startOfCalendarDay(window.end, calendar: calendar)
        let days = enumerateDays(from: rangeStart, through: rangeEndDay, calendar: calendar)
        guard !days.isEmpty else { return [] }

        let (_, standardQueryEnd) = dailyQueryBounds(
            from: rangeStart,
            through: rangeEndDay,
            calendar: calendar
        )

        let jobs = metricJobs(for: inclusion)
        guard !jobs.isEmpty else { return [] }

        var hrv: [Date: Double?] = [:]
        var rhr: [Date: Double?] = [:]
        var sleep = SchemaV2SleepSeries(total: [:], deep: [:], rem: [:])
        var steps: [Date: Double?] = [:]
        var weight: [Date: Double?] = [:]
        var bodyFatRaw: [Date: Double?] = [:]
        var activeEnergy: [Date: Double?] = [:]
        var restingEnergy: [Date: Double?] = [:]
        var exerciseMinutes: [Date: Double?] = [:]
        var calories: [Date: Double?] = [:]
        var protein: [Date: Double?] = [:]
        var carbs: [Date: Double?] = [:]
        var fat: [Date: Double?] = [:]
        var water: [Date: Double?] = [:]
        var alcohol: [Date: Double?] = [:]
        var workouts: [Date: [WorkoutLog]] = [:]
        var trainingLoad: [Date: Double?] = [:]

        try await withThrowingTaskGroup(of: MetricJobResult.self) { group in
            var jobIterator = jobs.makeIterator()

            func enqueueNext() {
                guard let job = jobIterator.next() else { return }
                group.addTask {
                    try await self.runMetricJob(
                        job,
                        days: days,
                        rangeStart: rangeStart,
                        standardQueryEnd: standardQueryEnd,
                        calendar: calendar,
                        includeTrainingLoadOnWorkouts: inclusion.trainingLoad
                    )
                }
            }

            let initialCount = min(Self.maxConcurrentMetricJobs, jobs.count)
            for _ in 0 ..< initialCount {
                enqueueNext()
            }

            for try await result in group {
                switch result {
                case .hrv(let values):
                    hrv = values
                case .rhr(let values):
                    rhr = values
                case .sleep(let series):
                    sleep = series
                case .steps(let values):
                    steps = values
                case .weight(let values):
                    weight = values
                case .bodyFat(let values):
                    bodyFatRaw = values
                case .activeEnergy(let values):
                    activeEnergy = values
                case .restingEnergy(let values):
                    restingEnergy = values
                case .exerciseMinutes(let values):
                    exerciseMinutes = values
                case .calories(let values):
                    calories = values
                case .protein(let values):
                    protein = values
                case .carbs(let values):
                    carbs = values
                case .fat(let values):
                    fat = values
                case .water(let values):
                    water = values
                case .alcohol(let values):
                    alcohol = values
                case .workouts(let values, let dailyLoad):
                    workouts = values
                    if !dailyLoad.isEmpty {
                        trainingLoad = dailyLoad
                    }
                case .trainingLoad(let values):
                    trainingLoad = values
                }
                enqueueNext()
            }
        }

        let timezoneIdentifier = TimeZone.current.identifier
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = calendar.timeZone

        return days.map { day in
            let dayKey = startOfCalendarDay(day, calendar: calendar)
            let bodyFatValue = bodyFatRaw[dayKey].flatMap { $0 }.map { $0 <= 1.0 ? $0 * 100.0 : $0 }
            let alcoholCount = alcohol[dayKey].flatMap { $0 }.map { Int($0.rounded()) }

            return DailyLog(
                date: formatter.string(from: dayKey),
                timezone: timezoneIdentifier,
                cnsAndCardio: CNSAndCardioMetrics(
                    restingHeartRate: inclusion.rhrToday ? RoundedDouble(rhr[dayKey].flatMap { $0 }) : nil,
                    hrvSdnn: inclusion.hrvToday ? RoundedDouble(hrv[dayKey].flatMap { $0 }) : nil
                ),
                sleepAndRecovery: SleepAndRecoveryMetrics(
                    sleepTotalMinutes: inclusion.sleepTotal ? RoundedDouble(sleep.total[dayKey].flatMap { $0 }) : nil,
                    deepSleepMinutes: inclusion.sleepDeep ? RoundedDouble(sleep.deep[dayKey].flatMap { $0 }) : nil,
                    remSleepMinutes: inclusion.sleepREM ? RoundedDouble(sleep.rem[dayKey].flatMap { $0 }) : nil
                ),
                nutritionAndToxicity: NutritionAndToxicityMetrics(
                    caloriesConsumedKcal: inclusion.caloriesConsumed
                        ? RoundedDouble(calories[dayKey].flatMap { $0 })
                        : nil,
                    proteinG: inclusion.proteinG ? RoundedDouble(protein[dayKey].flatMap { $0 }) : nil,
                    carbsG: inclusion.carbsG ? RoundedDouble(carbs[dayKey].flatMap { $0 }) : nil,
                    fatG: inclusion.fatG ? RoundedDouble(fat[dayKey].flatMap { $0 }) : nil,
                    waterLiters: inclusion.waterLiters ? RoundedDouble(water[dayKey].flatMap { $0 }) : nil,
                    alcoholicBeveragesCount: inclusion.alcoholicBeveragesCount ? alcoholCount : nil
                ),
                activityAndStrain: ActivityAndStrainMetrics(
                    stepCount: inclusion.stepCount ? steps[dayKey].flatMap { $0 }.map { Int($0.rounded()) } : nil,
                    activeEnergyKcal: inclusion.activeEnergy
                        ? RoundedDouble(activeEnergy[dayKey].flatMap { $0 })
                        : nil,
                    restingEnergyKcal: inclusion.restingEnergy
                        ? RoundedDouble(restingEnergy[dayKey].flatMap { $0 })
                        : nil,
                    exerciseMinutes: inclusion.exerciseMinutes
                        ? RoundedDouble(exerciseMinutes[dayKey].flatMap { $0 })
                        : nil,
                    trainingLoadContribution: inclusion.trainingLoad
                        ? RoundedDouble(trainingLoad[dayKey].flatMap { $0 })
                        : nil,
                    workouts: inclusion.workouts ? (workouts[dayKey] ?? []) : []
                ),
                bodyComposition: BodyCompositionMetrics(
                    bodyWeightKg: inclusion.weight ? RoundedDouble(weight[dayKey].flatMap { $0 }) : nil,
                    bodyFatPercent: inclusion.bodyFat ? RoundedDouble(bodyFatValue) : nil
                )
            )
        }
    }

    // MARK: - Parallel metric jobs

    private enum MetricJob: Sendable {
        case hrv
        case rhr
        case sleep
        case steps
        case weight
        case bodyFat
        case activeEnergy
        case restingEnergy
        case exerciseMinutes
        case calories
        case protein
        case carbs
        case fat
        case water
        case alcohol
        case workouts
        case trainingLoadOnly
    }

    private enum MetricJobResult: Sendable {
        case hrv([Date: Double?])
        case rhr([Date: Double?])
        case sleep(SchemaV2SleepSeries)
        case steps([Date: Double?])
        case weight([Date: Double?])
        case bodyFat([Date: Double?])
        case activeEnergy([Date: Double?])
        case restingEnergy([Date: Double?])
        case exerciseMinutes([Date: Double?])
        case calories([Date: Double?])
        case protein([Date: Double?])
        case carbs([Date: Double?])
        case fat([Date: Double?])
        case water([Date: Double?])
        case alcohol([Date: Double?])
        case workouts([Date: [WorkoutLog]], dailyTrainingLoad: [Date: Double?])
        case trainingLoad([Date: Double?])

        var progressName: String {
            switch self {
            case .hrv: return "HRV"
            case .rhr: return "resting heart rate"
            case .sleep: return "sleep"
            case .steps: return "steps"
            case .weight: return "weight"
            case .bodyFat: return "body fat"
            case .activeEnergy: return "active energy"
            case .restingEnergy: return "resting energy"
            case .exerciseMinutes: return "exercise minutes"
            case .calories: return "calories"
            case .protein: return "protein"
            case .carbs: return "carbs"
            case .fat: return "fat"
            case .water: return "water"
            case .alcohol: return "alcohol"
            case .workouts: return "workouts"
            case .trainingLoad: return "training load"
            }
        }
    }


    private func metricJobs(for inclusion: MetricInclusion) -> [MetricJob] {
        var jobs: [MetricJob] = []
        if inclusion.needsHRV { jobs.append(.hrv) }
        if inclusion.needsRHR { jobs.append(.rhr) }
        if inclusion.needsSleep { jobs.append(.sleep) }
        if inclusion.stepCount { jobs.append(.steps) }
        if inclusion.weight { jobs.append(.weight) }
        if inclusion.bodyFat { jobs.append(.bodyFat) }
        if inclusion.activeEnergy { jobs.append(.activeEnergy) }
        if inclusion.restingEnergy { jobs.append(.restingEnergy) }
        if inclusion.exerciseMinutes { jobs.append(.exerciseMinutes) }
        if inclusion.caloriesConsumed { jobs.append(.calories) }
        if inclusion.proteinG { jobs.append(.protein) }
        if inclusion.carbsG { jobs.append(.carbs) }
        if inclusion.fatG { jobs.append(.fat) }
        if inclusion.waterLiters { jobs.append(.water) }
        if inclusion.alcoholicBeveragesCount { jobs.append(.alcohol) }
        if inclusion.workouts {
            jobs.append(.workouts)
        } else if inclusion.trainingLoad {
            jobs.append(.trainingLoadOnly)
        }
        return jobs
    }

    private func runMetricJob(
        _ job: MetricJob,
        days: [Date],
        rangeStart: Date,
        standardQueryEnd: Date,
        calendar: Calendar,
        includeTrainingLoadOnWorkouts: Bool
    ) async throws -> MetricJobResult {
        try Task.checkCancellation()
        switch job {
        case .hrv:
            let values = await fetchDailyDiscreteAverages(
                identifier: .heartRateVariabilitySDNN,
                days: days,
                calendar: calendar
            )
            return .hrv(values)
        case .rhr:
            let values = await fetchDailyDiscreteAverages(
                identifier: .restingHeartRate,
                days: days,
                calendar: calendar
            )
            return .rhr(values)
        case .sleep:
            let series = await fetchSchemaV2SleepSeries(days: days, calendar: calendar)
            return .sleep(series)
        case .steps:
            let values = await fetchDailyCumulativeSums(
                identifier: .stepCount,
                unit: .count(),
                days: days,
                calendar: calendar
            )
            return .steps(values)
        case .weight:
            let values = await fetchDailyLatestQuantities(
                identifier: .bodyMass,
                unit: .gramUnit(with: .kilo),
                from: rangeStart,
                to: standardQueryEnd,
                calendar: calendar
            )
            return .weight(values)
        case .bodyFat:
            let values = await fetchDailyLatestQuantities(
                identifier: .bodyFatPercentage,
                unit: .percent(),
                from: rangeStart,
                to: standardQueryEnd,
                calendar: calendar
            )
            return .bodyFat(values)
        case .activeEnergy:
            let values = await fetchDailyCumulativeSums(
                identifier: .activeEnergyBurned,
                unit: .kilocalorie(),
                days: days,
                calendar: calendar
            )
            return .activeEnergy(values)
        case .restingEnergy:
            let values = await fetchDailyCumulativeSums(
                identifier: .basalEnergyBurned,
                unit: .kilocalorie(),
                days: days,
                calendar: calendar
            )
            return .restingEnergy(values)
        case .exerciseMinutes:
            let values = await fetchDailyCumulativeSums(
                identifier: .appleExerciseTime,
                unit: .minute(),
                days: days,
                calendar: calendar
            )
            return .exerciseMinutes(values)
        case .calories:
            let values = await fetchDailyCumulativeSums(
                identifier: .dietaryEnergyConsumed,
                unit: .kilocalorie(),
                days: days,
                calendar: calendar
            )
            return .calories(values)
        case .protein:
            let values = await fetchDailyCumulativeSums(
                identifier: .dietaryProtein,
                unit: .gram(),
                days: days,
                calendar: calendar
            )
            return .protein(values)
        case .carbs:
            let values = await fetchDailyCumulativeSums(
                identifier: .dietaryCarbohydrates,
                unit: .gram(),
                days: days,
                calendar: calendar
            )
            return .carbs(values)
        case .fat:
            let values = await fetchDailyCumulativeSums(
                identifier: .dietaryFatTotal,
                unit: .gram(),
                days: days,
                calendar: calendar
            )
            return .fat(values)
        case .water:
            let values = await fetchDailyCumulativeSums(
                identifier: .dietaryWater,
                unit: .liter(),
                days: days,
                calendar: calendar
            )
            return .water(values)
        case .alcohol:
            let values = await fetchDailyCumulativeSums(
                identifier: .numberOfAlcoholicBeverages,
                unit: .count(),
                days: days,
                calendar: calendar
            )
            return .alcohol(values)
        case .workouts:
            let (logs, dailyLoad) = try await fetchDailyWorkouts(
                days: days,
                calendar: calendar,
                attachEffortScores: includeTrainingLoadOnWorkouts
            )
            return .workouts(logs, dailyTrainingLoad: dailyLoad)
        case .trainingLoadOnly:
            let values = await fetchDailyTrainingLoadFromEffortSamples(days: days, calendar: calendar)
            return .trainingLoad(values)
        }
    }

    // MARK: - Calendar boundaries

    private nonisolated func localCalendar() -> Calendar {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        return calendar
    }

    private nonisolated func startOfCalendarDay(_ date: Date, calendar: Calendar) -> Date {
        BioharvestHealthKitMath.startOfCalendarDay(date, calendar: calendar)
    }

    private nonisolated func inclusiveEndOfCalendarDay(_ date: Date, calendar: Calendar) -> Date {
        BioharvestHealthKitMath.inclusiveEndOfCalendarDay(date, calendar: calendar)
    }

    private nonisolated func dailyQueryBounds(
        from rangeStartDay: Date,
        through rangeEndDay: Date,
        calendar: Calendar
    ) -> (start: Date, end: Date) {
        BioharvestHealthKitMath.dailyQueryBounds(
            from: rangeStartDay,
            through: rangeEndDay,
            calendar: calendar
        )
    }

    private nonisolated func exclusiveEndOfCalendarDay(_ date: Date, calendar: Calendar) -> Date {
        BioharvestHealthKitMath.exclusiveEndOfCalendarDay(date, calendar: calendar)
    }

    private func enumerateDays(from start: Date, through end: Date, calendar: Calendar) -> [Date] {
        var days: [Date] = []
        var current = startOfCalendarDay(start, calendar: calendar)
        let lastDay = startOfCalendarDay(end, calendar: calendar)
        while current <= lastDay {
            days.append(current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = startOfCalendarDay(next, calendar: calendar)
        }
        return days
    }

    // MARK: - HealthKit query helpers

    private func executeSampleQuery<Sample: HKSample>(
        sampleType: HKSampleType,
        predicate: NSPredicate?,
        sortDescriptors: [NSSortDescriptor]? = nil
    ) async -> [Sample] {
        await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sampleType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: sortDescriptors
            ) { [healthStore] activeQuery, results, error in
                defer { healthStore.stop(activeQuery) }
                if error != nil {
                    continuation.resume(returning: [])
                    return
                }
                continuation.resume(returning: results as? [Sample] ?? [])
            }
            healthStore.execute(query)
        }
    }

    private func executeStatisticsCollectionQuery(
        quantityType: HKQuantityType,
        predicate: NSPredicate,
        options: HKStatisticsOptions,
        anchorDate: Date,
        intervalComponents: DateComponents
    ) async -> HKStatisticsCollection? {
        await withCheckedContinuation { (continuation: CheckedContinuation<HKStatisticsCollection?, Never>) in
            let query = HKStatisticsCollectionQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: options,
                anchorDate: anchorDate,
                intervalComponents: intervalComponents
            )
            query.initialResultsHandler = { [healthStore] activeQuery, collection, error in
                defer { healthStore.stop(activeQuery) }
                if error != nil {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: collection)
                }
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Quantity queries (midnight-anchored standard metrics)

    private func fetchDailyCumulativeSums(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        days: [Date],
        calendar: Calendar
    ) async -> [Date: Double?] {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier), !days.isEmpty else {
            return [:]
        }

        let rangeStart = days[0]
        let rangeEndDay = days[days.count - 1]
        let (anchor, queryEnd) = dailyQueryBounds(from: rangeStart, through: rangeEndDay, calendar: calendar)
        let predicate = HKQuery.predicateForSamples(withStart: anchor, end: queryEnd, options: [])

        var dayInterval = DateComponents()
        dayInterval.day = 1

        let collection = await executeStatisticsCollectionQuery(
            quantityType: type,
            predicate: predicate,
            options: .cumulativeSum,
            anchorDate: anchor,
            intervalComponents: dayInterval
        )
        guard let collection else { return [:] }
        var result: [Date: Double?] = [:]
        for day in days {
            let dayKey = startOfCalendarDay(day, calendar: calendar)
            guard let statistics = collection.statistics(for: dayKey) else {
                result[dayKey] = nil
                continue
            }
            if let quantity = statistics.sumQuantity() {
                result[dayKey] = quantity.doubleValue(for: unit)
            } else {
                result[dayKey] = nil
            }
        }
        return result
    }

    private func fetchDailyDiscreteAverages(
        identifier: HKQuantityTypeIdentifier,
        days: [Date],
        calendar: Calendar
    ) async -> [Date: Double?] {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier), !days.isEmpty else {
            return [:]
        }

        let rangeStart = days[0]
        let rangeEndDay = days[days.count - 1]
        let (anchor, queryEnd) = dailyQueryBounds(from: rangeStart, through: rangeEndDay, calendar: calendar)
        let predicate = HKQuery.predicateForSamples(withStart: anchor, end: queryEnd, options: [])
        let unit = unit(for: type)

        var dayInterval = DateComponents()
        dayInterval.day = 1

        let collection = await executeStatisticsCollectionQuery(
            quantityType: type,
            predicate: predicate,
            options: .discreteAverage,
            anchorDate: anchor,
            intervalComponents: dayInterval
        )
        guard let collection else { return [:] }
        var result: [Date: Double?] = [:]
        for day in days {
            let dayKey = startOfCalendarDay(day, calendar: calendar)
            guard let statistics = collection.statistics(for: dayKey) else {
                result[dayKey] = nil
                continue
            }
            if let quantity = statistics.averageQuantity() {
                result[dayKey] = quantity.doubleValue(for: unit)
            } else {
                result[dayKey] = nil
            }
        }
        return result
    }

    private func fetchDailyLatestQuantities(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        from rangeStart: Date,
        to queryEnd: Date,
        calendar: Calendar
    ) async -> [Date: Double?] {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return [:] }

        let samples: [HKQuantitySample] = await executeSampleQuery(
            sampleType: type,
            predicate: HKQuery.predicateForSamples(withStart: rangeStart, end: queryEnd, options: []),
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)]
        )

        var result: [Date: Double?] = [:]
        for sample in samples {
            let dayStart = startOfCalendarDay(sample.endDate, calendar: calendar)
            let dayEnd = exclusiveEndOfCalendarDay(dayStart, calendar: calendar)
            guard sample.endDate >= dayStart, sample.endDate < dayEnd else { continue }
            result[dayStart] = sample.quantity.doubleValue(for: unit)
        }
        return result
    }

    // MARK: - Sleep (18:00 previous day to 18:00 log day)

    private struct SchemaV2SleepSeries: Sendable {
        let total: [Date: Double?]
        let deep: [Date: Double?]
        let rem: [Date: Double?]
    }

    private func fetchSchemaV2SleepSeries(days: [Date], calendar: Calendar) async -> SchemaV2SleepSeries {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis), !days.isEmpty else {
            return SchemaV2SleepSeries(total: [:], deep: [:], rem: [:])
        }

        let queryStart = BioharvestHealthKitMath.sleepWindowStart(for: days[0], calendar: calendar)
        let queryEnd = BioharvestHealthKitMath.sleepWindowEnd(for: days[days.count - 1], calendar: calendar)
        let sampleQueryEnd = calendar.date(byAdding: .second, value: 1, to: queryEnd) ?? queryEnd

        let samples: [HKCategorySample] = await executeSampleQuery(
            sampleType: sleepType,
            predicate: HKQuery.predicateForSamples(withStart: queryStart, end: sampleQueryEnd),
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        )

        let totalValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue
        ]
        let deepValues: Set<Int> = [HKCategoryValueSleepAnalysis.asleepDeep.rawValue]
        let remValues: Set<Int> = [HKCategoryValueSleepAnalysis.asleepREM.rawValue]

        let dayKeys = days.map { startOfCalendarDay($0, calendar: calendar) }
        let samplesByDay = Self.indexSleepSamplesByDay(
            samples: samples,
            dayKeys: dayKeys,
            calendar: calendar
        )

        var total: [Date: Double?] = [:]
        var deep: [Date: Double?] = [:]
        var rem: [Date: Double?] = [:]

        for dayKey in dayKeys {
            let windowStart = BioharvestHealthKitMath.sleepWindowStart(for: dayKey, calendar: calendar)
            let windowEnd = BioharvestHealthKitMath.sleepWindowEnd(for: dayKey, calendar: calendar)
            let daySamples = samplesByDay[dayKey] ?? []
            total[dayKey] = mergedDurationMinutes(
                from: daySamples,
                matching: totalValues,
                windowStart: windowStart,
                windowEnd: windowEnd
            )
            deep[dayKey] = mergedDurationMinutes(
                from: daySamples,
                matching: deepValues,
                windowStart: windowStart,
                windowEnd: windowEnd
            )
            rem[dayKey] = mergedDurationMinutes(
                from: daySamples,
                matching: remValues,
                windowStart: windowStart,
                windowEnd: windowEnd
            )
        }

        return SchemaV2SleepSeries(total: total, deep: deep, rem: rem)
    }

    // MARK: - Workouts (midnight-anchored local day)

    private func fetchDailyWorkouts(
        days: [Date],
        calendar: Calendar,
        attachEffortScores: Bool
    ) async throws -> ([Date: [WorkoutLog]], [Date: Double?]) {
        guard !days.isEmpty else { return ([:], [:]) }

        let rangeStart = days[0]
        let rangeEndDay = days[days.count - 1]
        let (queryStart, queryEnd) = dailyQueryBounds(from: rangeStart, through: rangeEndDay, calendar: calendar)
        let workoutType = HKObjectType.workoutType()

        let samples: [HKWorkout] = await executeSampleQuery(
            sampleType: workoutType,
            predicate: HKQuery.predicateForSamples(withStart: queryStart, end: queryEnd, options: []),
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        )

        var dayBuckets: [Date: [HKWorkout]] = [:]
        for day in days {
            dayBuckets[startOfCalendarDay(day, calendar: calendar)] = []
        }

        for workout in samples {
            let dayKey = startOfCalendarDay(workout.startDate, calendar: calendar)
            let dayStart = calendar.startOfDay(for: dayKey)
            let inclusiveEnd = inclusiveEndOfCalendarDay(dayKey, calendar: calendar)
            guard workout.startDate >= dayStart, workout.startDate <= inclusiveEnd else { continue }
            guard dayBuckets[dayKey] != nil else { continue }
            dayBuckets[dayKey, default: []].append(workout)
        }

        var effortByWorkoutUUID: [UUID: Double] = [:]
        if attachEffortScores {
            let allWorkouts = dayBuckets.values.flatMap { $0 }
            effortByWorkoutUUID = await fetchWorkoutEffortScores(for: allWorkouts)
        }

        var result: [Date: [WorkoutLog]] = [:]
        var dailyTrainingLoad: [Date: Double?] = [:]

        for (dayKey, dayWorkouts) in dayBuckets {
            let qualifyingWorkouts = dayWorkouts.filter {
                ($0.duration / 60.0) >= Self.minimumWorkoutDurationMinutes
            }
            var dayEffortSum = 0.0
            var hasEffort = false
            result[dayKey] = qualifyingWorkouts.map { workout in
                let effort = effortByWorkoutUUID[workout.uuid]
                if let effort {
                    dayEffortSum += effort
                    hasEffort = true
                }
                return WorkoutLog(
                    type: WorkoutActivityTypeFormatter.displayName(for: workout.workoutActivityType),
                    durationMinutes: RoundedDouble(workout.duration / 60.0),
                    energyBurnedKcal: RoundedDouble(
                        activeEnergyBurnedKilocalories(for: workout)
                    ),
                    effortScore: attachEffortScores ? RoundedDouble(effort) : nil,
                    trainingLoadContribution: attachEffortScores ? RoundedDouble(effort) : nil
                )
            }
            dailyTrainingLoad[dayKey] = hasEffort ? dayEffortSum : nil
        }

        return (result, attachEffortScores ? dailyTrainingLoad : [:])
    }

    private func activeEnergyBurnedKilocalories(for workout: HKWorkout) -> Double? {
        guard let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else {
            return nil
        }
        return workout.statistics(for: activeEnergyType)?
            .sumQuantity()?
            .doubleValue(for: .kilocalorie())
    }

    /// Batch-fetches `workoutEffortScore` samples for the given workouts in one range query.
    private func fetchWorkoutEffortScores(for workouts: [HKWorkout]) async -> [UUID: Double] {
        guard let effortType = HKQuantityType.quantityType(forIdentifier: .workoutEffortScore),
              !workouts.isEmpty,
              let queryStart = workouts.map(\.startDate).min(),
              let queryEnd = workouts.map(\.endDate).max()
        else { return [:] }

        let samples: [HKQuantitySample] = await executeSampleQuery(
            sampleType: effortType,
            predicate: HKQuery.predicateForSamples(withStart: queryStart, end: queryEnd, options: []),
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
        )

        var effortByWorkoutUUID: [UUID: Double] = [:]
        for sample in samples {
            guard let workout = Self.matchWorkout(for: sample, in: workouts),
                  effortByWorkoutUUID[workout.uuid] == nil
            else { continue }
            let raw = sample.quantity.doubleValue(for: .appleEffortScore())
            effortByWorkoutUUID[workout.uuid] = min(10, max(0, raw))
        }
        return effortByWorkoutUUID
    }

    /// Aggregates standalone `workoutEffortScore` samples per local calendar day (used when workouts list is excluded).
    private func fetchDailyTrainingLoadFromEffortSamples(
        days: [Date],
        calendar: Calendar
    ) async -> [Date: Double?] {
        guard let effortType = HKQuantityType.quantityType(forIdentifier: .workoutEffortScore),
              !days.isEmpty
        else { return [:] }

        let rangeStart = days[0]
        let rangeEndDay = days[days.count - 1]
        let (queryStart, queryEnd) = dailyQueryBounds(from: rangeStart, through: rangeEndDay, calendar: calendar)

        let samples: [HKQuantitySample] = await executeSampleQuery(
            sampleType: effortType,
            predicate: HKQuery.predicateForSamples(withStart: queryStart, end: queryEnd, options: []),
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        )

        var sums: [Date: Double] = [:]
        for day in days {
            sums[startOfCalendarDay(day, calendar: calendar)] = 0
        }

        for sample in samples {
            let dayKey = startOfCalendarDay(sample.startDate, calendar: calendar)
            guard sums[dayKey] != nil else { continue }
            let score = sample.quantity.doubleValue(for: .appleEffortScore())
            sums[dayKey, default: 0] += min(10, max(0, score))
        }

        var result: [Date: Double?] = [:]
        for day in days {
            let dayKey = startOfCalendarDay(day, calendar: calendar)
            let total = sums[dayKey] ?? 0
            result[dayKey] = total > 0 ? total : nil
        }
        return result
    }

    private nonisolated func unit(for type: HKQuantityType) -> HKUnit {
        switch type.identifier {
        case HKQuantityTypeIdentifier.heartRateVariabilitySDNN.rawValue:
            return .secondUnit(with: .milli)
        case HKQuantityTypeIdentifier.restingHeartRate.rawValue:
            return .count().unitDivided(by: .minute())
        default:
            return .count()
        }
    }

    private func mergedDurationMinutes(
        from samples: [HKCategorySample],
        matching values: Set<Int>,
        windowStart: Date,
        windowEnd: Date
    ) -> Double? {
        let intervals: [(start: Date, end: Date)] = samples
            .filter { values.contains($0.value) }
            .map { sample in
                let start = max(sample.startDate, windowStart)
                let end = min(sample.endDate, windowEnd)
                return (start, end)
            }
        return BioharvestHealthKitMath.mergedDurationMinutes(from: intervals)
    }

    private static func indexSleepSamplesByDay(
        samples: [HKCategorySample],
        dayKeys: [Date],
        calendar: Calendar
    ) -> [Date: [HKCategorySample]] {
        var buckets = Dictionary(uniqueKeysWithValues: dayKeys.map { ($0, [HKCategorySample]()) })
        guard !samples.isEmpty, !dayKeys.isEmpty else { return buckets }
        for sample in samples {
            for dayKey in dayKeys {
                let windowStart = BioharvestHealthKitMath.sleepWindowStart(for: dayKey, calendar: calendar)
                let windowEnd = BioharvestHealthKitMath.sleepWindowEnd(for: dayKey, calendar: calendar)
                guard sample.endDate > windowStart, sample.startDate < windowEnd else { continue }
                buckets[dayKey, default: []].append(sample)
            }
        }
        return buckets
    }

    private static func sampleMatchesWorkout(
        sampleStart: Date,
        workoutStart: Date,
        workoutEnd: Date,
        graceAfterEnd: TimeInterval = 300
    ) -> Bool {
        sampleStart >= workoutStart && sampleStart <= workoutEnd.addingTimeInterval(graceAfterEnd)
    }

    private static func matchWorkout(for sample: HKQuantitySample, in workouts: [HKWorkout]) -> HKWorkout? {
        workouts.first { workout in
            sampleMatchesWorkout(
                sampleStart: sample.startDate,
                workoutStart: workout.startDate,
                workoutEnd: workout.endDate
            )
        }
    }

}

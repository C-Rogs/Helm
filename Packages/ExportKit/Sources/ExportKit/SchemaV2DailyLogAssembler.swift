import Core
import Foundation

public enum SchemaV2DailyLogAssembler: Sendable {
    public static func assemble(
        days: [Date],
        inclusion: MetricInclusion,
        metrics: SchemaV2MetricBundle,
        calendar: Calendar,
        timezoneIdentifier: String = TimeZone.current.identifier
    ) -> [DailyLog] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = calendar.timeZone

        return days.map { day in
            let dayKey = BioharvestHealthKitMath.startOfCalendarDay(day, calendar: calendar)
            let bodyFatValue = metrics.bodyFat[dayKey]
                .flatMap { $0 }
                .flatMap(BodyFatPercent.storedPercent(fromHealthKitPercentUnit:))
            let alcoholCount = metrics.alcohol[dayKey].flatMap { $0 }.map { Int($0.rounded()) }

            return DailyLog(
                date: formatter.string(from: dayKey),
                timezone: timezoneIdentifier,
                cnsAndCardio: CNSAndCardioMetrics(
                    restingHeartRate: inclusion.rhrToday ? RoundedDouble(metrics.rhr[dayKey].flatMap { $0 }) : nil,
                    hrvSdnn: inclusion.hrvToday ? RoundedDouble(metrics.hrv[dayKey].flatMap { $0 }) : nil
                ),
                sleepAndRecovery: SleepAndRecoveryMetrics(
                    sleepTotalMinutes: inclusion.sleepTotal
                        ? RoundedDouble(metrics.sleep.total[dayKey].flatMap { $0 })
                        : nil,
                    deepSleepMinutes: inclusion.sleepDeep
                        ? RoundedDouble(metrics.sleep.deep[dayKey].flatMap { $0 })
                        : nil,
                    remSleepMinutes: inclusion.sleepREM
                        ? RoundedDouble(metrics.sleep.rem[dayKey].flatMap { $0 })
                        : nil
                ),
                nutritionAndToxicity: NutritionAndToxicityMetrics(
                    caloriesConsumedKcal: inclusion.caloriesConsumed
                        ? RoundedDouble(metrics.calories[dayKey].flatMap { $0 })
                        : nil,
                    proteinG: inclusion.proteinG ? RoundedDouble(metrics.protein[dayKey].flatMap { $0 }) : nil,
                    carbsG: inclusion.carbsG ? RoundedDouble(metrics.carbs[dayKey].flatMap { $0 }) : nil,
                    fatG: inclusion.fatG ? RoundedDouble(metrics.fat[dayKey].flatMap { $0 }) : nil,
                    waterLiters: inclusion.waterLiters ? RoundedDouble(metrics.water[dayKey].flatMap { $0 }) : nil,
                    alcoholicBeveragesCount: inclusion.alcoholicBeveragesCount ? alcoholCount : nil
                ),
                activityAndStrain: ActivityAndStrainMetrics(
                    stepCount: inclusion.stepCount
                        ? metrics.steps[dayKey].flatMap { $0 }.map { Int($0.rounded()) }
                        : nil,
                    activeEnergyKcal: inclusion.activeEnergy
                        ? RoundedDouble(metrics.activeEnergy[dayKey].flatMap { $0 })
                        : nil,
                    restingEnergyKcal: inclusion.restingEnergy
                        ? RoundedDouble(metrics.restingEnergy[dayKey].flatMap { $0 })
                        : nil,
                    exerciseMinutes: inclusion.exerciseMinutes
                        ? RoundedDouble(metrics.exerciseMinutes[dayKey].flatMap { $0 })
                        : nil,
                    trainingLoadContribution: inclusion.trainingLoad
                        ? RoundedDouble(metrics.trainingLoad[dayKey].flatMap { $0 })
                        : nil,
                    workouts: inclusion.workouts ? (metrics.workouts[dayKey] ?? []) : []
                ),
                bodyComposition: BodyCompositionMetrics(
                    bodyWeightKg: inclusion.weight ? RoundedDouble(metrics.weight[dayKey].flatMap { $0 }) : nil,
                    bodyFatPercent: inclusion.bodyFat ? RoundedDouble(bodyFatValue) : nil
                )
            )
        }
    }

    public static func exportRange(from logs: [DailyLog], window: SchemaV2ExportWindow, calendar: Calendar) -> ExportRange {
        if let first = logs.first?.date, let last = logs.last?.date {
            return ExportRange(startDate: first, endDate: last)
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = calendar.timeZone
        return ExportRange(
            startDate: formatter.string(from: window.start),
            endDate: formatter.string(from: window.end)
        )
    }
}

public enum SchemaV2ExportPipeline: Sendable {
    public static func buildPayload(
        window: SchemaV2ExportWindow,
        inclusion: MetricInclusion,
        logs: [DailyLog],
        healthKitStatus: HealthKitStatus,
        exportDate: Date = Date(),
        calendar: Calendar = SchemaV2ExportWindow.localCalendar()
    ) -> ExportPayload {
        ExportPayload(
            schemaVersion: ExportPayload.currentSchemaVersion,
            app: SchemaV2Validation.expectedApp,
            purpose: SchemaV2Validation.expectedPurpose,
            exportDate: exportDate,
            healthKitStatus: healthKitStatus,
            exportRange: SchemaV2DailyLogAssembler.exportRange(from: logs, window: window, calendar: calendar),
            logs: logs
        )
    }

    public static func resolveHealthKitStatus(
        authResult: SchemaV2AuthResult,
        logs: [DailyLog],
        inclusion: MetricInclusion
    ) -> HealthKitStatus {
        if logs.contains(where: { $0.hasAnyValue(for: inclusion) }) {
            return .liveAuthorized
        }

        switch authResult {
        case .unavailable: return .unavailable
        case .error: return .error
        case .notDetermined: return .notDetermined
        case .liveAuthorized, .denied: return .denied
        }
    }
}

public enum SchemaV2AuthResult: Sendable {
    case liveAuthorized
    case notDetermined
    case denied
    case unavailable
    case error
}

extension DailyLog {
    func hasAnyValue(for inclusion: MetricInclusion) -> Bool {
        cnsAndCardio.hasAnyValue(for: inclusion)
            || sleepAndRecovery.hasAnyValue(for: inclusion)
            || nutritionAndToxicity.hasAnyValue(for: inclusion)
            || activityAndStrain.hasAnyValue(for: inclusion)
            || bodyComposition.hasAnyValue(for: inclusion)
    }
}

extension CNSAndCardioMetrics {
    func hasAnyValue(for inclusion: MetricInclusion) -> Bool {
        if inclusion.hrvToday && hrvSdnn != nil { return true }
        if inclusion.rhrToday && restingHeartRate != nil { return true }
        return false
    }
}

extension SleepAndRecoveryMetrics {
    func hasAnyValue(for inclusion: MetricInclusion) -> Bool {
        if inclusion.sleepTotal && sleepTotalMinutes != nil { return true }
        if inclusion.sleepDeep && deepSleepMinutes != nil { return true }
        if inclusion.sleepREM && remSleepMinutes != nil { return true }
        return false
    }
}

extension NutritionAndToxicityMetrics {
    func hasAnyValue(for inclusion: MetricInclusion) -> Bool {
        if inclusion.caloriesConsumed && caloriesConsumedKcal != nil { return true }
        if inclusion.proteinG && proteinG != nil { return true }
        if inclusion.carbsG && carbsG != nil { return true }
        if inclusion.fatG && fatG != nil { return true }
        if inclusion.waterLiters && waterLiters != nil { return true }
        if inclusion.alcoholicBeveragesCount && alcoholicBeveragesCount != nil { return true }
        return false
    }
}

extension ActivityAndStrainMetrics {
    func hasAnyValue(for inclusion: MetricInclusion) -> Bool {
        if inclusion.stepCount && stepCount != nil { return true }
        if inclusion.activeEnergy && activeEnergyKcal != nil { return true }
        if inclusion.restingEnergy && restingEnergyKcal != nil { return true }
        if inclusion.exerciseMinutes && exerciseMinutes != nil { return true }
        if inclusion.trainingLoad && trainingLoadContribution != nil { return true }
        if inclusion.workouts && !workouts.isEmpty { return true }
        return false
    }
}

extension BodyCompositionMetrics {
    func hasAnyValue(for inclusion: MetricInclusion) -> Bool {
        if inclusion.weight && bodyWeightKg != nil { return true }
        if inclusion.bodyFat && bodyFatPercent != nil { return true }
        return false
    }
}

public enum GeminiClipboardHandoff: Sendable {
    public static let geminiAppURL = URL(string: "https://gemini.google.com/app")

    public static func clipboardText(json: String) -> String {
        """
        Health context export (bioharvest schema v2). Paste this into Gemini with your workout text and life notes.

        \(json)
        """
    }
}

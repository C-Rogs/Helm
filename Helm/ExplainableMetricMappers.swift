import Core
import DesignSystem
import Foundation
import HealthKitIngest
import NutritionKit
import ReadinessKit

enum ExplainableMetricMappers {
    static func readiness(_ score: ReadinessScore, coachAvailable: Bool) -> ExplainableMetric {
        let helmState = HelmState.readiness(score: Double(score.score))
        var contributors: [ExplainContributor] = [
            contributor(id: "hrv", label: "HRV", z: score.contributors.zHRV),
            contributor(id: "rhr", label: "Resting HR", z: score.contributors.zRestingHR),
            contributor(id: "sleep", label: "Sleep", z: score.contributors.zSleep),
        ]

        if score.contributors.zStrain != nil {
            contributors.append(contributor(id: "strain", label: "Strain", z: score.contributors.zStrain))
        }
        if score.contributors.zRespiratory != nil {
            contributors.append(contributor(id: "respiratory", label: "Respiratory", z: score.contributors.zRespiratory))
        }
        if score.contributors.zTemperature != nil {
            contributors.append(contributor(id: "temperature", label: "Temperature", z: score.contributors.zTemperature))
        }

        return ExplainableMetric(
            domain: "Readiness",
            title: "ARC Score",
            value: "\(score.score)",
            state: helmState,
            summary: readinessSummary(for: score),
            contributors: contributors,
            citation: ExplainCitation(id: "ev-readiness-arc", label: "ARC method"),
            coachPromptSeed: "Why is my ARC score \(score.score) today?",
            isCoachHandoffEnabled: coachAvailable
        )
    }

    static func prescriptionVolume(
        _ summary: PrescribedSessionSummary,
        baselineSets: Int?,
        coachAvailable: Bool
    ) -> ExplainableMetric {
        var contributors: [ExplainContributor] = []

        if let baselineSets {
            contributors.append(
                ExplainContributor(
                    id: "baseline",
                    label: "Baseline",
                    value: "\(baselineSets) sets",
                    detail: "Mesocycle target"
                )
            )
        }

        if summary.readinessAdjusted, let baselineSets {
            let delta = summary.totalSets - baselineSets
            let sign = delta >= 0 ? "+" : ""
            contributors.append(
                ExplainContributor(
                    id: "readiness",
                    label: "Readiness gate",
                    value: "\(sign)\(delta) sets",
                    detail: "Low ARC trim",
                    state: .depleted
                )
            )
        }

        contributors.append(
            ExplainContributor(
                id: "phase",
                label: "Phase",
                value: summary.phase.label,
                detail: TrainingPlanCoachContext.emphasisDisplayLabel(summary.emphasis) ?? summary.emphasis
            )
        )

        for exercise in summary.exercises {
            contributors.append(
                ExplainContributor(
                    id: exercise.id,
                    label: exercise.displayName,
                    value: "\(exercise.targetSets) sets",
                    detail: exercise.targetRepRange
                )
            )
        }

        let summaryText: String? = summary.readinessAdjusted
            ? "Volume trimmed because readiness is depleted."
            : nil

        return ExplainableMetric(
            domain: "Prescription",
            title: "Session volume",
            value: "\(summary.totalSets)",
            unit: "sets",
            state: summary.readinessAdjusted ? .compromised : .ready,
            summary: summaryText,
            contributors: contributors,
            citation: ExplainCitation(id: "ev-volume-landmarks", label: "MEV to MRV"),
            coachPromptSeed: baselineSets.map {
                "Why is today's session \(summary.totalSets) sets instead of \($0)?"
            } ?? "Why is today's session \(summary.totalSets) sets?",
            isCoachHandoffEnabled: coachAvailable
        )
    }

    static func nutrition(
        _ snapshot: NutritionDaySnapshot,
        coachAvailable: Bool
    ) -> ExplainableMetric {
        let targets = snapshot.targets
        let formattedCalories = targets.caloriesKcal > 0
            ? formattedInteger(targets.caloriesKcal)
            : "Pending"
        let floorApplied = targets.caloriesKcal > 0 && targets.caloriesKcal <= 1_200
        let budget = snapshot.weeklyBudget
        let budgetDay = snapshot.budgetDay

        var contributors: [ExplainContributor] = []

        if let profileMaintenance = snapshot.profileMaintenanceKcal, profileMaintenance > 0 {
            contributors.append(
                ExplainContributor(
                    id: "profile-maintenance",
                    label: "Profile maintenance",
                    value: "\(profileMaintenance) kcal",
                    detail: "Mifflin-St Jeor seed from body profile"
                )
            )
        }

        if targets.estimatedTDEEKcal > 0 {
            contributors.append(
                ExplainContributor(
                    id: "tdee",
                    label: "Adaptive TDEE",
                    value: "\(targets.estimatedTDEEKcal) kcal",
                    detail: tdeeDetail(snapshot)
                )
            )
        } else {
            contributors.append(
                ExplainContributor(
                    id: "tdee",
                    label: "Adaptive TDEE",
                    value: "Pending",
                    detail: "Complete body profile in Settings",
                    state: .compromised
                )
            )
        }

        if let budget {
            let dailyPool = budget.targetCaloriesKcal / 7
            let tdee = targets.estimatedTDEEKcal
            let adj = tdee > 0 ? dailyPool - tdee : 0
            contributors.append(
                ExplainContributor(
                    id: "weekly-pool",
                    label: "Weekly pool",
                    value: "\(budget.targetCaloriesKcal) kcal",
                    detail: phasePoolDetail(phase: snapshot.phase, dailyPool: dailyPool, tdee: tdee, adj: adj)
                )
            )
            contributors.append(
                ExplainContributor(
                    id: "week-remaining",
                    label: "Week remaining",
                    value: "\(budget.remainingCaloriesKcal) kcal",
                    detail: "\(budget.consumedCaloriesKcal) logged of \(budget.targetCaloriesKcal)"
                )
            )
        }

        if let intake = snapshot.trend.weeklyIntakeAverageKcal, intake > 0 {
            contributors.append(
                ExplainContributor(
                    id: "intake-avg",
                    label: "7-day diet average",
                    value: "\(Int(intake.rounded())) kcal",
                    detail: "Logged food only; not maintenance during a cut"
                )
            )
        }

        if let weight = snapshot.trend.smoothedTrendWeightKg {
            contributors.append(
                ExplainContributor(
                    id: "trend-weight",
                    label: "Trend weight",
                    value: String(format: "%.1f kg", weight),
                    detail: "EWMA of recent morning weigh-ins"
                )
            )
        }

        if let budgetDay {
            contributors.append(
                ExplainContributor(
                    id: "demand",
                    label: "Day demand",
                    value: budgetDay.demand.displayLabel,
                    detail: "Weights this day's share of the weekly pool and the carb/fat split"
                )
            )
            contributors.append(
                ExplainContributor(
                    id: "planned",
                    label: "Planned share",
                    value: "\(budgetDay.plannedCaloriesKcal) kcal",
                    detail: "Demand-weighted share before logging reflow"
                )
            )
            if budgetDay.isReflowed {
                let delta = budgetDay.eatToCaloriesKcal - budgetDay.plannedCaloriesKcal
                let sign = delta >= 0 ? "+" : ""
                contributors.append(
                    ExplainContributor(
                        id: "reflow",
                        label: "Reflow",
                        value: "\(sign)\(delta) kcal",
                        detail: "Unlocked days absorb leftover after locked intake",
                        state: delta < 0 ? .compromised : .ready
                    )
                )
            }
        } else {
            contributors.append(
                ExplainContributor(
                    id: "demand",
                    label: "Day type",
                    value: snapshot.dayType.rawValue.capitalized,
                    detail: "Weekly budget unavailable; showing seed macros"
                )
            )
        }

        contributors.append(
            ExplainContributor(
                id: "eat-to",
                label: "Eat-to",
                value: targets.caloriesKcal > 0 ? "\(targets.caloriesKcal) kcal" : "Pending",
                detail: "Authoritative calorie target for this day"
            )
        )

        contributors.append(
            ExplainContributor(
                id: "protein",
                label: "Protein",
                value: targets.proteinGrams > 0 ? "\(targets.proteinGrams) g" : "Pending",
                detail: "2.0 g/kg, held constant across the week"
            )
        )

        if floorApplied {
            contributors.append(
                ExplainContributor(
                    id: "floor",
                    label: "Safety floor",
                    value: "1,200 kcal",
                    detail: "Target cannot drop below minimum TDEE floor",
                    state: .compromised
                )
            )
        }

        contributors.append(contentsOf: [
            ExplainContributor(
                id: "carbs",
                label: "Carbohydrates",
                value: "\(targets.carbohydrateGrams) g",
                detail: budgetDay.map { "\($0.demand.displayLabel) share of remaining energy" }
                    ?? dayTypeDetail(snapshot.dayType)
            ),
            ExplainContributor(
                id: "fat",
                label: "Fat",
                value: "\(targets.fatGrams) g",
                detail: "Fills remaining energy after protein and carbs"
            ),
        ])

        if let logged = snapshot.loggedKcal {
            contributors.append(
                ExplainContributor(
                    id: "logged",
                    label: "Logged intake",
                    value: "\(logged) kcal",
                    detail: snapshot.remainingKcal >= 0
                        ? "\(snapshot.remainingKcal) kcal remaining"
                        : "\(-snapshot.remainingKcal) kcal over eat-to"
                )
            )
        }

        switch snapshot.activeEnergyFreshness {
        case let .fresh(burned):
            contributors.append(
                ExplainContributor(
                    id: "active",
                    label: "Active energy",
                    value: "\(burned) kcal",
                    detail: "Context only. Not added to eat-to; TDEE already includes habitual burn."
                )
            )
        case let .stale(partial):
            contributors.append(
                ExplainContributor(
                    id: "active",
                    label: "Active energy",
                    value: partial.map { "\($0) kcal" } ?? "Syncing",
                    detail: "HealthKit still catching up. Not added to eat-to.",
                    state: .compromised
                )
            )
        case .unavailable:
            break
        }

        if let gap = targets.macroGapKilocalories,
           gap > MacroGapCalculator.significanceThresholdKcal {
            contributors.append(
                ExplainContributor(
                    id: "gap",
                    label: "Untracked energy",
                    value: "+\(Int(gap.rounded())) kcal",
                    detail: "Alcohol or quick-add without full macros",
                    state: .depleted
                )
            )
        }

        let summary: String
        if floorApplied {
            summary = "Eat-to is at the 1,200 kcal safety floor. Adjust phase or body mass in Training Plan settings."
        } else if let budgetDay {
            let demand = budgetDay.demand.displayLabel
            if budgetDay.isReflowed {
                summary = "Eat-to is the weekly pool after locked days, weighted for \(demand). Planned share was \(budgetDay.plannedCaloriesKcal) kcal."
            } else {
                summary = "Eat-to is this \(demand) day's share of the weekly calorie pool. Active burn does not change it."
            }
        } else {
            summary = "\(snapshot.phase.label) phase. Weekly budget unavailable until body profile is complete."
        }

        return ExplainableMetric(
            domain: "Nutrition",
            title: "Eat-to",
            value: formattedCalories,
            unit: "kcal",
            state: .ready,
            summary: summary,
            contributors: contributors,
            citation: ExplainCitation(id: "ev-energy-balance", label: "Weekly energy budget"),
            coachPromptSeed: "Why is my eat-to \(formattedCalories) kcal today?",
            isCoachHandoffEnabled: coachAvailable
        )
    }

    private static func tdeeDetail(_ snapshot: NutritionDaySnapshot) -> String {
        if let adaptive = snapshot.trend.estimatedTDEEKcal,
           adaptive > 0,
           let profileMaintenance = snapshot.profileMaintenanceKcal,
           abs(Int(adaptive.rounded()) - profileMaintenance) > 25 {
            return "Refined from recent food logs and weight trend"
        }
        if snapshot.trend.estimatedTDEEKcal != nil {
            return "Refined from recent food logs and weight trend"
        }
        return "Using profile maintenance until enough weight and intake data"
    }

    private static func phasePoolDetail(
        phase: TrainingPhase,
        dailyPool: Int,
        tdee: Int,
        adj: Int
    ) -> String {
        switch phase {
        case .cut:
            return "Cut. \(dailyPool) kcal/day average, \(abs(adj)) below TDEE"
        case .gain:
            return "Gain. \(dailyPool) kcal/day average, \(abs(adj)) above TDEE"
        case .maintain:
            return "Maintain. \(dailyPool) kcal/day average from TDEE"
        }
    }

    private static func dayTypeDetail(_ dayType: NutritionDayType) -> String {
        switch dayType {
        case .training: "Training day share"
        case .rest: "Rest day share"
        case .deload: "Deload day share"
        }
    }

    private static func contributor(id: String, label: String, z: Double?) -> ExplainContributor {
        ExplainContributor(
            id: id,
            label: label,
            value: zValueText(z),
            detail: zDetailText(z),
            state: z.map(helmState(for:))
        )
    }

    private static func zValueText(_ z: Double?) -> String {
        guard let z else { return "N/A" }
        let sign = z >= 0 ? "+" : ""
        return "z \(sign)\(String(format: "%.1f", z))"
    }

    private static func zDetailText(_ z: Double?) -> String? {
        guard let z else { return "No data" }
        if z > 0.75 { return "Above baseline" }
        if z < -0.75 { return "Below baseline" }
        return "Near baseline"
    }

    private static func helmState(for z: Double) -> HelmState {
        if z > 0.75 { return .primed }
        if z < -0.75 { return .depleted }
        return .ready
    }

    private static func readinessSummary(for score: ReadinessScore) -> String {
        switch score.confidence {
        case .high:
            return "\(score.band.rawValue.capitalized) recovery with \(score.validNights) baseline nights."
        case .medium:
            return "Provisional score with \(score.validNights)/14 baseline nights."
        case .low:
            return "Low confidence while the baseline is still forming."
        }
    }

    private static func formattedInteger(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

private extension TrainingPhase {
    var label: String {
        switch self {
        case .cut: "Cut"
        case .maintain: "Maintain"
        case .gain: "Gain"
        }
    }
}

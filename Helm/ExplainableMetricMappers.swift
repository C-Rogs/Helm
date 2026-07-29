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
                detail: summary.emphasisProgressLabel ?? summary.emphasis
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

        var contributors: [ExplainContributor] = []

        if let profileMaintenance = snapshot.profileMaintenanceKcal, profileMaintenance > 0 {
            contributors.append(
                ExplainContributor(
                    id: "profile-maintenance",
                    label: "Profile maintenance",
                    value: "\(profileMaintenance) kcal",
                    detail: "Starting estimate from body profile"
                )
            )
        }

        if targets.estimatedTDEEKcal > 0 {
            let tdeeDetail: String
            if let adaptive = snapshot.trend.estimatedTDEEKcal,
               adaptive > 0,
               let profileMaintenance = snapshot.profileMaintenanceKcal,
               abs(Int(adaptive.rounded()) - profileMaintenance) > 25 {
                tdeeDetail = "Refined from recent food logs and weight trend"
            } else if snapshot.trend.estimatedTDEEKcal != nil {
                tdeeDetail = "Refined from recent food logs and weight trend"
            } else {
                tdeeDetail = "Using profile maintenance until enough weight and intake data"
            }
            contributors.append(
                ExplainContributor(
                    id: "tdee",
                    label: "Current TDEE estimate",
                    value: "\(targets.estimatedTDEEKcal) kcal",
                    detail: tdeeDetail
                )
            )
        } else {
            contributors.append(
                ExplainContributor(
                    id: "tdee",
                    label: "Current TDEE estimate",
                    value: "Pending",
                    detail: "Complete body profile in Settings",
                    state: .compromised
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

        contributors.append(contentsOf: [
            ExplainContributor(
                id: "phase",
                label: "Phase adjustment",
                value: phaseAdjustmentLabel(for: snapshot.phase),
                detail: phaseAdjustmentDetail(for: snapshot.phase)
            ),
            ExplainContributor(
                id: "protein",
                label: "Protein floor",
                value: targets.proteinGrams > 0 ? "\(targets.proteinGrams) g" : "Pending",
                detail: "2.0 g/kg minimum"
            ),
            ExplainContributor(
                id: "daytype",
                label: "Day type",
                value: snapshot.dayType.rawValue.capitalized,
                detail: "Affects carb/fat split only, not calories"
            ),
        ])

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
                detail: dayTypeDetail(snapshot.dayType)
            ),
            ExplainContributor(
                id: "fat",
                label: "Fat",
                value: "\(targets.fatGrams) g",
                detail: "Remaining calories"
            ),
        ])

        if let actual = snapshot.actual?.totalEnergy {
            contributors.append(
                ExplainContributor(
                    id: "logged",
                    label: "Logged intake",
                    value: "\(Int(actual.kilocalories.rounded())) kcal",
                    detail: "HealthKit actuals"
                )
            )
        }

        if let gap = targets.macroGapKilocalories,
           gap > MacroGapCalculator.significanceThresholdKcal {
            contributors.append(
                ExplainContributor(
                    id: "gap",
                    label: "Untracked energy",
                    value: "+\(Int(gap.rounded())) kcal",
                    detail: "Alcohol or untracked macros",
                    state: .depleted
                )
            )
        }

        let summary: String
        if floorApplied {
            summary = "Calorie target is at the 1,200 kcal safety floor. Adjust phase or body mass in Training Plan settings."
        } else if let gap = targets.macroGapKilocalories,
           gap > MacroGapCalculator.significanceThresholdKcal {
            summary = "\(snapshot.phase.label) phase \(snapshot.dayType.rawValue) day. Untracked energy is shown separately from macro targets."
        } else {
            summary = "\(snapshot.phase.label) phase \(snapshot.dayType.rawValue) day with \(targets.proteinGrams)g protein."
        }

        return ExplainableMetric(
            domain: "Nutrition",
            title: "Calorie target",
            value: formattedCalories,
            unit: "kcal",
            state: .ready,
            summary: summary,
            contributors: contributors,
            citation: ExplainCitation(id: "ev-energy-balance", label: "Energy balance"),
            coachPromptSeed: "Why is my calorie target \(formattedCalories) kcal today?",
            isCoachHandoffEnabled: coachAvailable
        )
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

    private static func phaseAdjustmentDetail(for phase: TrainingPhase) -> String {
        switch phase {
        case .cut: "500 kcal deficit from TDEE"
        case .gain: "300 kcal surplus to TDEE"
        case .maintain: "Maintenance calories"
        }
    }

    private static func phaseAdjustmentLabel(for phase: TrainingPhase) -> String {
        switch phase {
        case .cut: "-\(Int(phaseAdjustmentKcal(for: phase))) kcal"
        case .gain: "+\(Int(phaseAdjustmentKcal(for: phase))) kcal"
        case .maintain: "0 kcal"
        }
    }

    private static func phaseAdjustmentKcal(for phase: TrainingPhase) -> Double {
        switch phase {
        case .cut: 500
        case .gain: 300
        case .maintain: 0
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

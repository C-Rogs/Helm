import Core
import DesignSystem
import Foundation
import HealthKitIngest
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
                detail: summary.emphasis
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
        _ targets: NutritionTargetsSummary,
        phase: TrainingPhase,
        coachAvailable: Bool
    ) -> ExplainableMetric {
        let formattedCalories = formattedInteger(targets.caloriesKcal)

        return ExplainableMetric(
            domain: "Nutrition",
            title: "Calorie target",
            value: formattedCalories,
            unit: "kcal",
            state: .ready,
            summary: "\(phase.label) phase \(targets.dayType) day with \(targets.proteinGrams)g protein.",
            contributors: [
                ExplainContributor(
                    id: "protein",
                    label: "Protein floor",
                    value: "\(targets.proteinGrams) g",
                    detail: "2.0 g/kg"
                ),
                ExplainContributor(
                    id: "carbs",
                    label: "Carbohydrates",
                    value: "\(targets.carbohydrateGrams) g",
                    detail: targets.dayType == "training" ? "Training day share" : "Rest day share"
                ),
                ExplainContributor(
                    id: "fat",
                    label: "Fat",
                    value: "\(targets.fatGrams) g",
                    detail: "Remaining calories"
                ),
                ExplainContributor(
                    id: "phase",
                    label: "Phase",
                    value: phase.label,
                    detail: phaseAdjustmentDetail(for: phase)
                ),
            ],
            citation: ExplainCitation(id: "ev-energy-balance", label: "Energy balance"),
            coachPromptSeed: "Why is my calorie target \(formattedCalories) kcal today?",
            isCoachHandoffEnabled: coachAvailable
        )
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
        case .cut: "500 kcal deficit"
        case .gain: "300 kcal surplus"
        case .maintain: "Maintenance calories"
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

import Foundation

public extension ExplainableMetric {
    static let readinessFixture = ExplainableMetric(
        domain: "Readiness",
        title: "ARC Score",
        value: "61",
        state: .ready,
        summary: "Balanced recovery with typical HRV and solid sleep.",
        contributors: [
            ExplainContributor(id: "hrv", label: "HRV", value: "z +0.5", detail: "Above baseline", state: .ready),
            ExplainContributor(id: "rhr", label: "Resting HR", value: "z -0.1", detail: "Near baseline", state: .ready),
            ExplainContributor(id: "sleep", label: "Sleep", value: "z +0.3", detail: "Near baseline", state: .ready),
            ExplainContributor(id: "strain", label: "Strain", value: "z -0.4", detail: "Below baseline", state: .compromised),
        ],
        citation: ExplainCitation(id: "ev-readiness-arc", label: "ARC method"),
        coachPromptSeed: "Why is my ARC score 61 today?",
        isCoachHandoffEnabled: true
    )

    static let prescriptionVolumeFixture = ExplainableMetric(
        domain: "Prescription",
        title: "Session volume",
        value: "14",
        unit: "sets",
        state: .compromised,
        summary: "Volume trimmed because readiness is depleted.",
        contributors: [
            ExplainContributor(id: "baseline", label: "Baseline", value: "18 sets", detail: "Mesocycle target"),
            ExplainContributor(id: "readiness", label: "Readiness gate", value: "-4 sets", detail: "Low ARC trim", state: .depleted),
            ExplainContributor(id: "phase", label: "Phase", value: "Gain", detail: "Week 3 accumulating"),
        ],
        citation: ExplainCitation(id: "ev-volume-landmarks", label: "MEV to MRV"),
        coachPromptSeed: "Why is today's session 14 sets instead of 18?",
        isCoachHandoffEnabled: true
    )

    static let nutritionTargetFixture = ExplainableMetric(
        domain: "Nutrition",
        title: "Calorie target",
        value: "2,760",
        unit: "kcal",
        state: .ready,
        summary: "Gain phase training day with 150g protein.",
        contributors: [
            ExplainContributor(id: "tdee", label: "Maintenance", value: "2,475 kcal", detail: "33 kcal/kg at 75 kg"),
            ExplainContributor(id: "phase", label: "Phase surplus", value: "+300 kcal", detail: "Gain phase"),
            ExplainContributor(id: "protein", label: "Protein floor", value: "150 g", detail: "2.0 g/kg"),
            ExplainContributor(id: "day", label: "Day type", value: "Training", detail: "Higher carb share"),
        ],
        citation: ExplainCitation(id: "ev-energy-balance", label: "Energy balance"),
        coachPromptSeed: "Why is my calorie target 2,760 kcal today?",
        isCoachHandoffEnabled: true
    )

    static let readinessOfflineFixture = readinessFixture.disablingCoachHandoff()
}

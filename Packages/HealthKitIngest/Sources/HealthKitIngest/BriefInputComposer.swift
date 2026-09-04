import Core
import Foundation
import PlanKit
import ReadinessKit

public enum BriefInputComposer {
    public static func compose(
        helmDay: HelmDay,
        readiness: ReadinessScore?,
        prescriptionSummary: PrescribedSessionSummary?,
        prescriptionSession: PrescribedSession?,
        nutritionSnapshot: NutritionDaySnapshot,
        patternLine: String? = nil
    ) -> BriefInputsSnapshot {
        let readinessSnapshot = BriefReadinessSnapshot(
            score: readiness?.score,
            band: readiness.map { ReadinessBand.classify(score: $0.score).rawValue },
            confidence: readiness?.confidence.rawValue,
            validNights: readiness?.validNights
        )

        let prescriptionSnapshot = prescriptionSummary.map { summary in
            let evidenceIDs = prescriptionSession?.exercises.flatMap(\.evidenceIDs) ?? []
            return BriefPrescriptionSnapshot(
                title: summary.title,
                phase: summary.phase.label,
                emphasis: summary.emphasis,
                exerciseCount: summary.exercises.count,
                totalSets: summary.totalSets,
                readinessAdjusted: summary.readinessAdjusted,
                evidenceIDs: Array(Set(evidenceIDs)).sorted()
            )
        }

        let nutrition = nutritionSnapshot.targets.summary
        let nutritionWithStatus = NutritionTargetsSummary(
            caloriesKcal: nutrition.caloriesKcal,
            proteinGrams: nutrition.proteinGrams,
            carbohydrateGrams: nutrition.carbohydrateGrams,
            fatGrams: nutrition.fatGrams,
            dayType: nutrition.dayType,
            intakeLoggingComplete: nutritionSnapshot.loggingComplete
        )

        return BriefInputsSnapshot(
            helmDay: helmDay,
            readiness: readinessSnapshot,
            prescription: prescriptionSnapshot,
            nutrition: nutritionWithStatus,
            patternLine: patternLine
        )
    }
}

private extension TrainingPhase {
    var label: String {
        switch self {
        case .cut: "cut"
        case .maintain: "maintain"
        case .gain: "gain"
        }
    }
}

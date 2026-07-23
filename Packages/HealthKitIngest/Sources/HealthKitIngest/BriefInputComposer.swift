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
        phase: TrainingPhase,
        bodyMassKg: Double?
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
                phase: summary.phase.label,
                emphasis: summary.emphasis,
                exerciseCount: summary.exercises.count,
                totalSets: summary.totalSets,
                readinessAdjusted: summary.readinessAdjusted,
                evidenceIDs: Array(Set(evidenceIDs)).sorted()
            )
        }

        let nutrition = NutritionTargetComposer.compose(
            phase: phase,
            bodyMassKg: bodyMassKg,
            isTrainingDay: (prescriptionSummary?.totalSets ?? 0) > 0
        )

        return BriefInputsSnapshot(
            helmDay: helmDay,
            readiness: readinessSnapshot,
            prescription: prescriptionSnapshot,
            nutrition: nutrition
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

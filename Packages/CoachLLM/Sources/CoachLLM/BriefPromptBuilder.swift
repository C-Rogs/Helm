import Core
import Foundation

public enum BriefPromptBuilder {
    public static func build(
        profile: MemoryProfile,
        inputs: BriefInputsSnapshot,
        evidenceRecords: [EvidenceRecord]
    ) -> CoachPrompt {
        let systemInstructions = CoachSystemPrompt.morningBriefV1
        let contextBlock = assembleContextBlock(
            profile: profile,
            inputs: inputs,
            evidenceRecords: evidenceRecords
        )
        let estimatedTokens = TokenBudget.estimateTokens(
            characterCount: systemInstructions.count + contextBlock.count
        )
        return CoachPrompt(
            systemInstructions: systemInstructions,
            contextBlock: contextBlock,
            estimatedTokens: estimatedTokens,
            includedDayCount: 1,
            droppedDayCount: 0
        )
    }

    private static func assembleContextBlock(
        profile: MemoryProfile,
        inputs: BriefInputsSnapshot,
        evidenceRecords: [EvidenceRecord]
    ) -> String {
        var sections = [
            "# Memory Profile\n\(profile.stablePrefixText())",
            "# Engine Snapshot\n\(engineSnapshotText(inputs))"
        ]

        let evidence = EvidenceIndex.stableText(from: evidenceRecords)
        if !evidence.isEmpty {
            sections.append("# Evidence Index\n\(evidence)")
        }

        return sections.joined(separator: "\n\n")
    }

    private static func engineSnapshotText(_ inputs: BriefInputsSnapshot) -> String {
        var lines = ["day=\(inputs.helmDay.formatted)"]

        if let score = inputs.readiness.score {
            lines.append("readiness=\(score)")
        }
        if let band = inputs.readiness.band {
            lines.append("readiness_band=\(band)")
        }
        if let confidence = inputs.readiness.confidence {
            lines.append("confidence=\(confidence)")
        }

        if let prescription = inputs.prescription {
            lines.append("phase=\(prescription.phase)")
            if let emphasis = prescription.emphasis, !emphasis.isEmpty {
                lines.append("emphasis=\(emphasis)")
            }
            lines.append("exercises=\(prescription.exerciseCount)")
            lines.append("total_sets=\(prescription.totalSets)")
            if prescription.readinessAdjusted {
                lines.append("readiness_adjusted=true")
            }
            if !prescription.evidenceIDs.isEmpty {
                lines.append("evidence_ids=\(prescription.evidenceIDs.joined(separator: ","))")
            }
        } else {
            lines.append("prescription=none")
        }

        let nutrition = inputs.nutrition
        lines.append("nutrition_kcal=\(nutrition.caloriesKcal)")
        lines.append("nutrition_protein_g=\(nutrition.proteinGrams)")
        lines.append("nutrition_carbs_g=\(nutrition.carbohydrateGrams)")
        lines.append("nutrition_fat_g=\(nutrition.fatGrams)")
        lines.append("nutrition_day_type=\(nutrition.dayType)")
        lines.append("intake_logging_complete=\(nutrition.intakeLoggingComplete)")

        return lines.joined(separator: "\n")
    }
}

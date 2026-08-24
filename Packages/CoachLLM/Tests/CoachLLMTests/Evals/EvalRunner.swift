import CoachLLM
import Core
import Foundation

struct EvalResult: Sendable {
    let scenarioID: String
    let passed: Bool
    let failures: [String]
}

enum EvalRunner {
    static func run(
        scenario: EvalScenario,
        provider: CoachLLMProvider,
        bundle: Bundle = .module
    ) async -> EvalResult {
        var failures: [String] = []

        let contextBlock = buildContextBlock(from: scenario)
        let stream: AsyncThrowingStream<String, Error>
        do {
            stream = try await provider.respond(
                systemInstructions: "You are a strength and nutrition coach. Respond with structured JSON.",
                contextBlock: contextBlock,
                userMessage: scenario.userPrompt,
                thread: .empty,
                freshnessSuffix: nil
            )
        } catch {
            return EvalResult(
                scenarioID: scenario.id,
                passed: false,
                failures: ["Provider error: \(error)"]
            )
        }

        let responseText: String
        do {
            responseText = try await FixtureStreamHarness.reassemble(stream)
        } catch {
            return EvalResult(
                scenarioID: scenario.id,
                passed: false,
                failures: ["Stream error: \(error)"]
            )
        }

        switch scenario.category {
        case "happyPath", "fatigue", "safety":
            failures.append(contentsOf: assertSessionAdjustment(responseText: responseText, scenario: scenario))
        case "nutrition":
            failures.append(contentsOf: assertNutrition(responseText: responseText, scenario: scenario))
        default:
            failures.append("Unknown scenario category: \(scenario.category)")
        }

        if !scenario.expectedCitations.isEmpty {
            failures.append(contentsOf: assertCitations(responseText: responseText, scenario: scenario))
        }

        return EvalResult(
            scenarioID: scenario.id,
            passed: failures.isEmpty,
            failures: failures
        )
    }

    // MARK: - Context building

    private static func buildContextBlock(from scenario: EvalScenario) -> String {
        var parts: [String] = []

        if !scenario.contextDays.readinessBaselines.isEmpty {
            parts.append(scenario.contextDays.readinessBaselines)
        }

        if !scenario.contextDays.recent.isEmpty {
            parts.append("Recent days:")
            for day in scenario.contextDays.recent {
                parts.append("- \(day.helmDay.formatted): \(day.text)")
            }
        }

        if !scenario.contextDays.recentWorkouts.isEmpty {
            parts.append(scenario.contextDays.recentWorkouts)
        }

        if !scenario.contextDays.trainingPlanSnapshot.isEmpty {
            parts.append(scenario.contextDays.trainingPlanSnapshot)
        }

        if !scenario.contextDays.nutritionDiary.isEmpty {
            parts.append(scenario.contextDays.nutritionDiary)
        }

        if !scenario.contextDays.todayPrescription.isEmpty {
            parts.append(scenario.contextDays.todayPrescription)
        }

        if !scenario.contextDays.engineProfile.isEmpty {
            parts.append(scenario.contextDays.engineProfile)
        }

        return parts.joined(separator: "\n\n")
    }

    // MARK: - Session adjustment assertions

    private static func assertSessionAdjustment(responseText: String, scenario: EvalScenario) -> [String] {
        var failures: [String] = []

        let payload: SessionAdjustmentPayload
        do {
            let jsonText = extractJSONBlock(from: responseText) ?? responseText
            payload = try CoachStructuredOutputDecoder.decode(
                SessionAdjustmentPayload.self,
                from: jsonText,
                expectedSchema: .sessionAdjustmentV2
            )
        } catch {
            return ["Failed to decode session adjustment: \(error)"]
        }

        let bounds = scenario.expectedBounds

        if let mustContain = bounds.mustContainKind {
            let operationKinds = Set(payload.operations.map(\.kind.rawValue))
            for kind in mustContain where !operationKinds.contains(kind) {
                failures.append("Expected operation kind '\(kind)' not found in \(operationKinds)")
            }
        }

        if let mustNotContain = bounds.mustNotContainKind {
            let operationKinds = Set(payload.operations.map(\.kind.rawValue))
            for kind in mustNotContain where operationKinds.contains(kind) {
                failures.append("Forbidden operation kind '\(kind)' found")
            }
        }

        if scenario.mustNotIncrease {
            for op in payload.operations where op.kind == .adjustLoad {
                if let delta = op.massDeltaKg, delta > 0 {
                    failures.append("Load increase (+\(delta)kg) when mustNotIncrease is set")
                }
            }
        }

        if scenario.mustSwapExercise {
            let hasSwap = payload.operations.contains { $0.kind == .swap && $0.toExerciseID != nil }
            if !hasSwap {
                failures.append("Expected exercise swap but none found")
            }
        }

        if let maxSetDelta = bounds.maxSetDelta {
            for op in payload.operations where op.kind == .adjustSets {
                if let delta = op.setDelta, abs(delta) > maxSetDelta {
                    failures.append("Set delta \(delta) exceeds max \(maxSetDelta)")
                }
            }
        }

        if let maxLoadDelta = bounds.maxLoadDeltaKg {
            for op in payload.operations where op.kind == .adjustLoad {
                if let delta = op.massDeltaKg, abs(delta) > maxLoadDelta {
                    failures.append("Load delta \(delta)kg exceeds max \(maxLoadDelta)kg")
                }
            }
        }

        if let phase = bounds.phaseConstraint {
            switch phase {
            case "deload", "rest":
                let hasLoadIncrease = payload.operations.contains {
                    $0.kind == .adjustLoad && ($0.massDeltaKg ?? 0) > 0
                }
                let hasSetIncrease = payload.operations.contains {
                    $0.kind == .adjustSets && ($0.setDelta ?? 0) > 0
                }
                if hasLoadIncrease || hasSetIncrease {
                    failures.append("Phase constraint '\(phase)' violated: load or set increase found")
                }
            default:
                break
            }
        }

        return failures
    }

    // MARK: - Nutrition assertions

    private static func assertNutrition(responseText: String, scenario: EvalScenario) -> [String] {
        var failures: [String] = []

        let bounds = scenario.expectedBounds

        if let payload = tryDecodeMealEstimate(from: responseText) {
            if let minCal = bounds.minCaloriesKcal, payload.caloriesKcal < minCal {
                failures.append("Calories \(payload.caloriesKcal) below min \(minCal)")
            }
            if let maxCal = bounds.maxCaloriesKcal, payload.caloriesKcal > maxCal {
                failures.append("Calories \(payload.caloriesKcal) above max \(maxCal)")
            }
            if let minP = bounds.minProteinG, payload.proteinG < minP {
                failures.append("Protein \(payload.proteinG)g below min \(minP)g")
            }
            if let maxP = bounds.maxProteinG, payload.proteinG > maxP {
                failures.append("Protein \(payload.proteinG)g above max \(maxP)g")
            }
            return failures
        }

        if let payload = tryDecodeFoodLog(from: responseText) {
            if let minCal = bounds.minCaloriesKcal, let cal = payload.caloriesKcal, cal < minCal {
                failures.append("Calories \(cal) below min \(minCal)")
            }
            if let maxCal = bounds.maxCaloriesKcal, let cal = payload.caloriesKcal, cal > maxCal {
                failures.append("Calories \(cal) above max \(maxCal)")
            }
            if let minP = bounds.minProteinG, let p = payload.proteinG, p < minP {
                failures.append("Protein \(p)g below min \(minP)g")
            }
            if let maxP = bounds.maxProteinG, let p = payload.proteinG, p > maxP {
                failures.append("Protein \(p)g above max \(maxP)g")
            }
            return failures
        }

        return ["Failed to decode nutrition payload from response"]
    }

    private static func tryDecodeMealEstimate(from text: String) -> MealEstimatePayload? {
        guard let json = extractJSONBlock(from: text) else { return nil }
        return try? CoachStructuredOutputDecoder.decode(
            MealEstimatePayload.self,
            from: json,
            expectedSchema: .mealEstimateV1
        )
    }

    private static func tryDecodeFoodLog(from text: String) -> FoodLogPayload? {
        guard let json = extractJSONBlock(from: text) else { return nil }
        return try? CoachStructuredOutputDecoder.decode(
            FoodLogPayload.self,
            from: json,
            expectedSchema: .foodLogV1
        )
    }

    // MARK: - Citation assertions

    private static func assertCitations(responseText: String, scenario: EvalScenario) -> [String] {
        var failures: [String] = []

        let brief: MorningBriefPayload
        do {
            let json = extractJSONBlock(from: responseText) ?? responseText
            brief = try CoachStructuredOutputDecoder.decode(
                MorningBriefPayload.self,
                from: json,
                expectedSchema: .briefV1
            )
        } catch {
            return []
        }

        let validationMap = CitationValidationMap(
            evidenceRecords: scenario.contextDays.evidence
        )

        for citationID in brief.citationIDs {
            if !validationMap.isValidEvidence(citationID) {
                failures.append("Phantom citation: '\(citationID)' not in evidence index")
            }
        }

        for expectedID in scenario.expectedCitations {
            if !brief.citationIDs.contains(expectedID) {
                failures.append("Missing expected citation: '\(expectedID)'")
            }
        }

        return failures
    }

    // MARK: - Helpers

    private static func extractJSONBlock(from text: String) -> String? {
        CoachEmbeddedJSONBlockFinder.blocks(in: text).first
    }
}